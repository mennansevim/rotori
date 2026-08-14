# DECISIONS.md — Mühendislik Kararları

> Sadece **append**. Eski kayıt silinmez; yanlış çıkarsa altına yeni bir
> kayıt eklenir ve orijinali *supersedes* alanıyla bağlanır.

---

## 2026-08-14h — Harita tile'ları önceden indirilmez ve diskte tutulmaz

**Supersedes:** `2026-07-x — Harita: OSM raster tile + kendi cache` kararının
cache bölümü ile `2026-08-14e` kaydındaki Google raster sağlayıcısı ayrıntısı.

**Karar:** Uygulama içi üç harita yüzeyi standart OSM raster katmanını tek
`RotoriTileProvider` üzerinden kullanır. Sağlayıcı yalnız Flutter'ın oturum içi
bellek cache'ine izin verir; `prewarmTiles`, “Çevrimdışı hazırla”, 30 günlük
disk cache ve `flutter_cache_manager` bağımlılığı kaldırılmıştır. Attribution
OSM telif sayfasına bağlanır. Google Maps yalnız kullanıcının açık navigasyon
eylemiyle dış uygulama olarak açılır.

Standart OSM servisi düşük hacimli TestFlight içindir. Genel App Store ölçeği
öncesinde ticari kullanım/SLA ve gerekiyorsa offline paket hakkı veren bir
sağlayıcı seçilmelidir; endpoint tek sabitten değiştirilebilir.

**Neden:** Önceki Google raster endpoint'i belgelenmiş mobil SDK akışı değildi;
toplu ön-indirme ve sabit süreli disk cache sağlayıcı politikalarıyla uyumlu
değildi. Ürün, garanti edemediği çevrimdışı haritayı vaat etmemelidir.

---

## 2026-08-14g — Viewer hero'ları telefon genişliğinde tek kompozisyondur

**Karar:** Harita şablonundaki tarih şeridi sabit çip genişliği kullanmaz;
mevcut telefon genişliği günler arasında eşit paylaşılır ve yatay kaydırma
kapatılır. Yolculuk şablonunun üst alanı Japonya çizgi sanatı, dört parçalı
ilerleme halkası ve mavi “Sıradaki” kartıyla referans kompozisyona yaklaştırılır.

**Neden:** Sabit genişlikli tarih kartları dar telefonda şeridi ekrandan
taşırıyordu. Önceki Yolculuk hero'su ise yalnız standart ilerleme göstergesi ve
metin kullandığı için seçilen görsel tasarımın Tokyo/Fuji dengesini vermiyordu.

---

## 2026-08-14f — Harita düzenlemesi seçili güne kilitlidir

**Supersedes:** `2026-08-14e` kaydındaki “Düzenleme modunda tüm günlerin
görünmesi korunur” ayrıntısı.

**Karar:** Harita şablonunda kalem düğmesi haritayı veya tarih şeridini
kaldırmaz. Düzenleme boyunca yalnız seçili günün günlük rota kartı çizilir ve
yalnız o günün aktiviteleri değiştirilebilir. Kullanıcı başka bir tarih çipine
bastığında harita, tek rota kartı ve düzenleme hedefi birlikte yeni güne geçer.

Tarih çiplerinde görsel ikon kullanılmaz. Kompakt dikdörtgenler gün, ay ve
hafta gününü gösterir; günler düşük yoğunluklu farklı renklerle ayrılır, seçili
gün ise ana vurgu rengi ve daha güçlü çerçeveyle belirtilir.

**Neden:** Harita üstünde tek aktif rota gösterilirken düzenlemede tüm günleri
açmak iki farklı aktiflik modeli yaratıyordu. Görüntüleme ve düzenleme hedefini
aynı seçili gün durumuna bağlamak yanlış günü değiştirme riskini kaldırır.

---

## 2026-08-14e — Harita şablonunda tek aktif gün vardır

**Karar:** Harita şablonundaki tarih çipleri ayrı bir modal açmaz. Seçilen çip
tek aktif gün durumunu değiştirir; üstteki harita durakları/rota çizgisi ve
haritanın hemen altındaki günlük timeline birlikte aynı güne geçer. Seçili
olmayan günlerin rota kartları Harita görünümünde çizilmez. Düzenleme modunda
tüm günlerin görünmesi korunur.

Harita yüzeyi mevcut Google raster yol haritası katmanını, GPS'ten çözülmüş gün
duraklarını, beyaz halo üstünde mavi rota çizgisini ve numaralı pembe pinleri
kullanır. Katman/konum kontrolleri seçili günün ayrıntılı haritasını açar.

**Neden:** Tarih çipinin ayrı harita açması ve altta bütün günlerin kalması,
aynı anda birden fazla “aktif rota” algısı yaratıyordu. Tek gün kaynağı,
kullanıcının “29 seçiliyken yalnız 29 Ağustos rotası” beklentisini veri
mutasyonu yapmadan açık ve test edilebilir hale getirir.

---

## 2026-08-14d — İlk iki viewer düzeni Yolculuk ve Harita'dır

**Supersedes:** `2026-08-14c` kaydındaki Ferah Kartlar / Kompakt Akış seçenek
adları ve görsel kapsamı. Tema ile düzenin ayrılması, tek seçim, yerel
kalıcılık ve plan verisinden bağımsızlık aynen korunur.

**Karar:** Kullanıcıya sunulan iki düzen **Yolculuk** (`journeyProgress`) ve
**Harita** (`mapFocus`) olacaktır. Yolculuk görünümü aktif günün tamamlanma
oranını ve sıradaki aktiviteyi ana kahraman yüzeyinde gösterir. Harita görünümü
aktif günün koordinatı doğrulanmış duraklarını, rota çizgisini ve gün seçimini
listenin üstünde gösterir; tam harita mevcut günlük harita ekranına açılır.

Eski/ara QA anahtarları (`calm-cards`, `compact-timeline`) sırasıyla yeni iki
seçeneğe okunabilir; yeni kayıtlar yalnız `journey-progress` ve `map-focus`
değerlerini yazar. Böylece geliştirme sırasında kaydedilmiş yerel tercih de
çökme veya boş görünüm üretmez.

**Neden:** Kullanıcı görsel keşifte ilerleme-odaklı ve harita-öncelikli iki
tasarımı açıkça seçti. Bunlar yalnız yoğunluk farkı değil, seyahat sırasında iki
ayrı zihinsel modele karşılık gelir: “sırada ne var?” ve “neredeyim/nereye
gidiyorum?”.

---

## 2026-08-14c — Viewer tema ve düzen şablonunu ayrı tercihler olarak saklar

**Karar:** Viewer görünümü iki bağımsız, tek seçimli eksene ayrılır. `Tema`
yalnız renk paletini (`japanDark`, `appleLight`, `sakuraSoft`), `Düzen` ise gün
kartlarının bilgi yoğunluğunu belirler. İlk düzen seçenekleri **Ferah Kartlar**
(`calmCards`, varsayılan) ve **Kompakt Akış** (`compactTimeline`) olacaktır.
Kullanıcı iki seçenekten birini seçer; iki düzen aynı anda birleşmez.

`viewer:template` yalnız görsel tercih olarak `SharedPreferences` içinde
saklanır. Eski kurulumda anahtar yoksa veya değer tanınmıyorsa Ferah Kartlar'a
düşülür. Şablon değişikliği `Trip`, `DayPlan`, rota snapshot'ı veya plan edit
komutlarını değiştirmez; bu yüzden tema/düzen değişimi veri kaybı ve plan
senkronu üretmez.

**Neden:** Mevcut üç tema renkleri değiştiriyor fakat kart yoğunluğunu
değiştirmiyordu. Ferah görünüm ile dar ekranda daha fazla satır gösteren kompakt
görünümü aynı veri ve davranış katmanı üstünde tutmak, ikinci bir viewer
uygulaması oluşturmadan gerçek bir kullanıcı seçimi sağlar.

---

## 2026-08-14b — LLM rota adayı üretir; deterministik motor kabul kararını verir

**Supersedes:** `2026-07-30 — Rota sırasını AI değil yönlü matris +
deterministik motor belirler` kaydındaki “AI rotayı değiştiremez” ayrıntısı.
Yönlü matrisin süre kaynağı, hard constraint'ler ve deterministik motorun nihai
karar yetkisi değişmez.

**Karar:** İlk plan önce mevcut beam-search + saha bağlamı + bağımsız validator
hattından geçer. LLM yalnız mevcut aktivite kümesi içinde **sıra adayı**
üretebilir; yeni yer ekleyemez, yer silemez veya gün değiştiremez. Yalnız
ölçülebilir karmaşıklığı en yüksek üç gün modele gider. Strict JSON Schema'dan
geçen aday `PlanScheduleEngine` ile güvenli taslağa uygulanır, ardından yalnız
etkilenen günlerde beam aramasına yumuşak ipucu verilerek aynı rota motorunda
yeniden optimize edilir. Aktivite sayısı/must-do koruması, route snapshot
kapsamı ve profil-ağırlıklı gerçek rota objective skoru deterministik tabandan
en az %2 iyi değilse aday reddedilir. Böylece model kararı değil arama uzayına
semantik bir öneri verir; kabul ölçülebilir ve tekrar üretilebilir kalır.

**Performans:** Aynı plan/prompt/model isteği cache'lenir. Model hatası veya
timeout plan üretimini bozmaz. LLM aşaması ayrı süre, cache, öneri, kabul/red ve
skor farkı metrikleri üretir; “LLM kaliteyi artırdı” iddiası ancak bu A/B
sinyalleriyle yapılır. Deterministik sıcak yolda aynı saha ulaşım değerlemesi
istek ömrü boyunca memoize edilir; cache sonucu planlar arasında paylaşılmaz.

**Neden:** Doğrudan LLM mutasyonu geçerli olsa bile daha uzun bir rota
üretebilir ve `PlanScheduleEngine` değişikliği mevcut route snapshot'ını
geçersizleştirir. Yeniden optimizasyon + skor kapısı bu iki riski kapatırken
LLM'in kullanıcı niyeti ve semantik bağlamdaki gücünü korur.

---

## 2026-08-14 — Viewer drawer üç bölümlüdür; Tema Hesap altında yer alır

**Supersedes:** `2026-08-12b` ve `2026-08-01` kayıtlarındaki ayrı Araçlar
bölümü ayrıntısı. Inset-group yüzey dili ve Tema seçicinin davranışı değişmez.

**Karar:** Viewer drawer **Yolculuk → Keşfet → Hesap** sırasını kullanır.
Tek satır kalan Araçlar bölümü ve başlığı kaldırılır. Tema seçici, seyahat
öncesi hazırlık, planlar ve hata bildirimiyle birlikte Hesap ayar grubunda
sunulur.

**Neden:** Tek öğeli Araçlar bölümü menüde gereksiz bir başlık, dikey boşluk
ve ayrı kart üretiyordu. Tema bir görünüm tercihi olduğu için hesap ve uygulama
ayarlarıyla aynı grupta daha doğal bulunur; davranış kaybetmeden drawer daha
kısa ve daha hızlı taranır.

---

## 2026-08-12b — Viewer drawer tek sakin inset-group dili kullanır

**Supersedes:** `2026-08-10c` kaydındaki fiyat etiketi tarayıcının gradyan
vitrin kartı olması ve Keşfet'in 2×2 küçük kartlarla sunulması ayrıntısı.
Özelliklerin kapsamı, Premium sınırı ve navigasyon davranışı değişmez.

**Karar:** Viewer drawer'ın Yolculuk, Keşfet, Araçlar ve Hesap bölümleri aynı
açık renkli, ince kenarlıklı inset-group sistemini kullanır. Keşfet'teki fiyat
tarayıcı, macera rehberi, hava, bütçe, checklist ve Rotori Eats tek grupta;
ikon, başlık, kısa açıklama ve chevron taşıyan satırlar olarak sunulur.
Premium durumu küçük ve düşük doygunluklu bir rozetle belirtilir. Keşfet içinde
gradyan vitrin, büyük gölge ve iki sütunlu kart ızgarası kullanılmaz.

**Neden:** Drawer'ın üstündeki yolculuk kartları ve altındaki hesap listesi
sakin ve okunabilirken ortadaki iki yüksek doygunluklu vitrin ile dört ayrı
renkli karo bütün hiyerarşiyi bozuyordu. Tek yüzey sistemi daha hızlı taranır,
daha az kaydırma ister ve büyük yazı boyutunda daha öngörülebilir genişler.

**Erişilebilirlik:** Her satır en az 56 px dokunma alanına sahiptir; başlık ve
açıklama görünür kalır, ikon tek başına anlam taşımak zorunda değildir.

---

## 2026-08-12a — Tam gün tema parkı ziyaret bütçesi kalabalıkla ikinci kez büyütülmez

**Karar:** `themepark` / `theme park` kategorisindeki tam gün blokları
`CrowdSensitivity.none` kabul edilir. Bu blokların 8 saatlik ziyaret bütçesi
kuyruk ve park içi dolaşımı zaten içerir; Sakura/Golden Week çarpanını tekrar
uygulamak aynı yoğunluğu iki kez sayar. İstasyon yürüyüşü ve ulaşım saha
düzeltmeleri uygulanmaya devam eder.

100×4 QA planlayıcısı `fullDayExclusive` ve `excursion` önceliğini ikinci
optimizasyon isteğinde de `mustDo` olarak korur. Tam gün parkı bulunan günde
otelden çıkış en geç 08:00 alınır; 09:00 rastgele günlük başlangıç tercihi
park açılışına yetişmeyi engellemez.

**Kanıt:** İlk field-aware stres koşusu DisneySea'yı 184 kez düşürerek %3
bırakma kapısını aştı. Öncelik koruması bu hatayı görünür biçimde infeasible
yaptı; süre semantiği ve erken çıkış düzeltmesinden sonra aynı seed ile
100 base × 4 profil / 3.748 optimizer gününde **0 infeasible, 0 hard ihlal,
0 must-do kaybı** ve **%2,58 bırakma** elde edildi.

---

## 2026-08-11m — Saha bağlamı üretimde zorunludur ve retry boyunca korunur

**Supersedes:** `2026-08-11l` kararındaki `field == null` kullanımının üretim
kalite kapılarına da uygulanabileceği yorumu. Null davranış yalnız geriye
uyumluluk sözleşmesi olarak kalır.

**Karar:** `PlanOptimizationController` her normal rota isteğinde plan günü,
baskın şehir, parti, JR Pass, bagaj, kapanış ve tekrar sinyallerinden
`FieldRealityContext` kurar. `OptimizationRequest` yeniden oluşturulan bütün
retry/dropping yollarında `field` aynen kopyalanır. Field-aware optimizer
başarısızsa aynı hard kapıları çalıştırmayan yerel sıralama fallback'i başarılı
rota gibi sunulmaz. Bağımsız validator, field ile düzeltilmiş transit bacağını
ham matris değerine karşılaştırmak yerine aynı saf saha modelini yeniden
uygular.

**JSON:** Kanonik plan kökü `Trip.toJson()` çıktısıdır ve
`schemaVersion: 3` üretir. Şema ile gerçek persistence/export belgesi bu alan
üzerinden aynı sürümü taşır.

**İstasyon ve trafik:** Japonca büyük istasyon adları açık alias listesiyle
çözülür; yalnız şehir kanjisini içeren mekanlar istasyon sayılmaz. Hafta içi
peak/off-peak çarpanlarına ek olarak hafta sonu ve resmî tatilde 1.15 leisure
riski uygulanır.

**Kalite kapısı:** 100×4 optimizer harness'ı her optimizer gününde field
bağlamını açar ve `fieldRealityCoveragePass` ölçer. Dropping + shifted-holiday,
Japonca istasyon alias'ı, hafta sonu/resmî tatil trafiği, controller saha
bağlantısı ve plan-v3 kök sürümü ayrı regresyonlardır.

---

## 2026-08-11l — Saha gerçekliği motorun içine değil, çevresine eklenir (v3)

**Karar:** Japonya'ya özgü lojistik/ulaşım/takvim gerçekleri
`BeamSearchItineraryOptimizer`'ın gövdesine gömülmez. Bunun yerine:

1. **İkili kapılar** `HardConstraintChecker`, **sürekli maliyet**
   `CostFunction` sınıflarına çıkarıldı. Motor artık yalnız arama stratejisini
   (beam 6 + 3 local-improvement turu) yönetir. v2'de bu iki mantık `_append`
   içinde iç içeydi; yeni bir saha kuralı eklemek skorlamayı sessizce
   bozabiliyordu.
2. Saha bilgisi tek bir **opsiyonel** `FieldRealityContext` ile taşınır.
   `field == null` iken motor v2 davranışını **birebir** korur.

**Kanıt:** 4132 optimizer günü / 17.700 aktivite üzerinde koşan üretim
harness'ının tam JSON zarfı refactor öncesi ve sonrası **byte-identical**
(strict 3818 · dropping ile kurtarılan 314 · infeasible 0 · hardViolation 0 ·
duplicateActivity 0 · mustDoDropped 0 · missingReturnLeg 0).

**Katmanlar (hepsi saf, `DateTime.now()` ve ağ yok):**

- `japan_calendar.dart` — resmî tatiller (Happy Monday, equinox formülü,
  振替休日, 国民の休日), teishukubi kapanış çözümleyicisi ve sezonluk kalabalık.
- `japan_transit_realism.dart` — JR Pass kapsamı, istasyon karmaşıklığı,
  karayolu trafik risk matrisi.
- `luggage_logistics.dart` — Coin Locker / Hotel Drop / Yamato karar ağacı ve
  otel check-in penceresi.
- `place_identity_resolver.dart` — Kanji/Kana/Romaji kanonikleştirme.
- `route_field_context.dart` — tekrar politikası + saha bağlamı toplayıcısı.
- `minute_math.dart` — çarpan zincirlerinde tek dakikalık kayan nokta kaymasını
  engelleyen ortak yuvarlama sözleşmesi.

**Pass kapsamı dışı servis iki farklı yerde iki farklı biçimde ele alınır.**
Rota matrisi somut bir Nozomi seferi verdiyse seçenek **reject** edilir —
onu "aslında Hikari'ydi" diye yeniden etiketlemek sahada var olmayan bir tren
uydurmaktır. Şehirlerarası geçiş satırı ise **tahmindir**; orada servis adı
Hikari/Sakura'ya yazılır ve süre %20/%10 uzatılır
(`PassExclusionBehaviour`).

**Ulusal JR Pass ve Nozomi:** Ekim 2023'ten beri ek ücretle Nozomi/Mizuho'ya
biniş mümkündür. Rotori **varsayılan olarak** bunu geçersiz sayar — kullanıcıya
"pass'in yeter" deyip istasyonda sürpriz ücret çıkarmamak ürün kararıdır.
Gerçek davranış `RailPassPolicy.allowNozomiWithSurcharge` ile temsil edilebilir.

**Freezed:** Proje hâlâ freezed'siz (bkz. `types.dart` başlığındaki Faz 3b
notu). v3 modelleri freezed'e taşınmaya hazır biçimde el yazımı immutable
sınıflar olarak yazıldı: `const` constructor, `final` alanlar, `copyWith`,
`toJson`/`tryFromJson`. Tek bir katman için codegen altyapısı kurulmadı.

**Bilinen sınır:** Tüm süreler ve ücretler tahmindir. Canlı tren gecikmesi ve
gerçek zamanlı trafik verisi kapsam dışıdır; bu yüzden risk taşıyan her
düzeltme UI'a `TransitDisclaimer` olarak taşınır ve kullanıcıya kesinlik vaadi
verilmez. Kanji→okuma dönüşümü **kapalı bir sözlükle** yapılır; sözlükte
olmayan kanji romaji üretmez ve kimlik kanji'nin kendisine düşer — sessiz
yanlış eşleşme yerine eşleşmeme tercih edilir.

---

## 2026-08-11k — Mobil eSIM önerisinin sağlayıcısı eSIM.io'dur

**Karar:** Hazırlık ve plan ekranlarındaki Japonya eSIM kartı eSIM.io markasını
açıkça gösterir ve eSIM.io'nun kanonik Japonya ürün sayfasına gider:
`https://esim.io/destinations/esim-japan`.

**Supersedes:** `2026-08-11j` kararının dış-link güvenliği politikası aynen
korunur; yalnız o bakım sırasında geçici olarak seçilen Airalo kanonik hedefi
ürün tercihi gereği eSIM.io ile değiştirilmiştir.

---

## 2026-08-11j — Dış önerilerde tahmini affiliate kimliği kullanılmaz

**Karar:** Mobil öneri kataloğunda yalnız sağlayıcının gerçekten üretip
Rotori'ye verdiği takip bağlantıları kullanılabilir. Aktif ve doğrulanmış bir
partner hedefi yoksa kart, takip parametresi olmadan sağlayıcının kanonik ürün
veya ülke sayfasına gider. Marka adına bakarak `aid=rotori`, `aff=rotori`,
`/affiliate/rotori` veya vanity `pxf.io/rotori-*` adresi türetilmez.

Katalog testleri HTTPS, host, user-info/fragment yokluğu ve tahmini takip
işaretlerini statik kalite kapısı olarak denetler. Canlı ağ kontrolü release
bakımının parçasıdır; bot koruması HTTP istemcisini reddetse bile hedef,
sağlayıcının tarayıcıda açılan ve arama dizininde görülen kanonik sayfası
olmalıdır.

**Neden:** Affiliate ağlarında okunabilir slug veya sorgu parametresi geçerli
ortaklık kaydı anlamına gelmez. Bu varsayım Airalo ve Klook'ta doğrudan 404,
Booking'de ise takip parametresi atılarak ilgisiz ana sayfaya düşme üretti.
Kullanıcı güveni ve çalışan satın alma akışı, doğrulanmamış komisyon
atfından önce gelir.

---

## 2026-08-11i — Sonradan uçuş ekleme tek açık kayıttır ve yalnız sınır günlerini yeniler

**Karar:** Plan oluşturulduktan sonra açılan uçuş formu alan değişikliklerini
arka planda kalıcılaştırmaz. Kullanıcı yerel bir taslak düzenler ve sayfanın
altındaki tek “Kaydet” aksiyonu uçuş bacaklarını, uçuş tercihlerini ve uçuşa
bağlı varış/dönüş günlerini tek plan snapshot'ı olarak kaydeder. Ayrı
“Günleri yeniden düzenle” aksiyonu kaldırılmıştır.

Kaydet işlemi bütün geziyi yeniden üretmez; yalnız ilk varış ve son dönüş
gününü uçuş saatlerine göre kurar. Aradaki günlerdeki manuel rota düzenlemeleri
aynen korunur. Başarı bilgisi kapatılınca uçuş sayfası güncel planı viewer'a
döndürür; viewer edit session'ı yeniler, sandviç panelini açar ve “Uçuşlar”
akordiyonunu genişletir.

**Neden:** Alan-bazlı debounce kaydı kullanıcının hangi anda değişikliği
tamamladığını belirsizleştiriyor; ayrıca ikinci yenileme butonu kayıt ve rota
güncellemesini iki ayrı görev gibi gösteriyordu. Bütün günleri yeniden üretmek
ise uçuşla ilgisiz manuel plan düzenlemelerini silebilirdi. Tek açık kayıt ve
sınır-günü yenilemesi işlemi anlaşılır ve veri kaybına karşı güvenli tutar.

---

## 2026-08-11h — Geçiş seçimi tek kaynak, mekan tekrarı kanonik kimlikle engellenir

**Karar:** `DayPlan.cityTransition`, şehirlerarası ulaşım seçiminin tek doğru
kaynağıdır. Kullanıcı modu değiştirdiğinde `PlanScheduleEngine`, yalnız seçim
alanını değil `isCityTransition` işaretli timeline satırını, süre/ücret
özetini, moda bağlı gün başlığını ve rota snapshot'ını aynı immutable komutta
yeniler. Yeni planlarda geçiş satırı açık metadata taşır; eski planlarda şehir
çiftiyle birebir eşleşen transport satırı geriye uyumlu olarak tanınır.

Aktivitenin plan içi örnek kimliği (`TimelineItem.id`) ile katalog mekan
kimliği (`TimelineItem.placeId`) ayrılır. Üretici `PlaceSuggestion` ve
`CityPlace` kaynaklarını şehir + kanonik mekan kimliğiyle birleştirir. Kontrollü
alias'lar (`usj`, `os-usj`, “Universal Studios”, “Universal Studios Japan”)
aynı mekanı gösterir. Ardışık iki günde aynı kanonik mekanın önerilmesi üretim
çıktısı için hard ihlaldir; farklı yemek/ulaşım satırları bu kurala dahil
değildir.

**Neden:** Yalnız `cityTransition.mode` alanını güncellemek üst rozeti doğru
gösterirken eski JR/Shinkansen timeline satırını bırakıyordu. Benzer biçimde
görünür ada göre birleştirme, aynı USJ kaydını iki katalog kimliğiyle iki güne
yerleştirebiliyordu. Her iki hata da kullanıcıya tek plan içinde çelişkili
talimat veriyor.

**Kalite kapısı:** Sentetik 100×4 profil optimizer harness'ı korunur. Buna ek
olarak gerçek `buildTripFromCities` üretim hattı 100'den fazla şehir sırası,
gezi uzunluğu ve dil kombinasyonunda çalıştırılır; ardışık kanonik tekrar,
geçiş modu/timeline uyumu ve eski mod metni sızıntısı sıfır olmalıdır. Sonuç
versioned JSON inceleme paketi olarak dışarı verilir.

---

## 2026-08-11g — İlk sürüm rota matrisi ücretli API yerine cihazdaki Japonya paketiyle çalışır

**Supersedes:** `2026-08-11f` kaydındaki Supabase `route-matrix` Edge Function
ve Google Routes çalışma zamanı entegrasyonu ayrıntısı. İlk planın kayıt
öncesinde mevcut beam-search + validator hattından geçmesi değişmez.

**Karar:** Rotori ilk sürümde Google Routes veya başka ücretli rota API'sini
çalışma zamanında çağırmaz. Varsayılan `RouteMatrixRepository`, uygulamayla
paketlenen ve sürümlenen offline Japonya ulaşım modelidir. Tokyo, Kyoto, Osaka
ve Hiroshima semt/istasyon kümeleriyle; diğer desteklenen şehirler kalibre
şehir profiliyle çalışır. Bilinmeyen noktalar muhafazakâr genel profile düşer.

Her yön için yürüyüş, şehrin baskın toplu taşıma modu ve taksi seçenekleri;
ilk/son yürüyüş, ortalama bekleme, araç içi süre, aktarma, büyük istasyon
tamponu, yol/sokak dolaşıklığı, hafta içi/sonu ve sabah/akşam yön etkisinden
üretilir. Küratörlü zor bağlantılar genel formülü geçersiz kılabilir. Sonuç
`estimated` ve `rotori-offline-jp` sağlayıcı kimliklidir; doğrulanmamış hat,
peron veya yön adı üretilmez.

**Neden:** Rotori'nin ana değeri canlı turn-by-turn navigasyon değil,
uygulanabilir günlük sıra ve zaman planıdır. Mevcut deterministik optimizer bu
kararı zaten verir; ücretli API yalnız matris girdisini iyileştiriyordu ve
küçük bir planda bile eleman bazlı maliyet büyüyordu. Sürümlü offline paket
maliyeti sıfırlar, uçakta çalışır, aynı girdide aynı sonucu verir ve kullanıcı
konumlarını üçüncü tarafa göndermez.

**Sınır:** Offline paket canlı tren gecikmesi, hat kesintisi, peron ve trafik
garantisi vermez. Kullanıcı gerçek zamanlı yönlendirme istediğinde açıkça
Apple/Google Maps'e geçebilir. Paket kalitesi saha senaryoları ve insan
incelemesiyle periyodik kalibre edilir; canlı veri yokken kesinlik iddiası
yapılmaz.

**Başlangıç planı koruması:** Koordinatı doğrulanmayan mola/özel başlık rota
düğümü sayılmaz. Kısmen dolu günlere rastgele yeni aktivite eklenmez; yalnız
öğün molası eklenebilir. Tam/yarım gün isteyen Disney, USJ ve teamLab kendi gün
şablonları dışında dolgu olarak kullanılamaz. Bu koruma beam-search ve hard
validator davranışını değiştirmeden, optimizasyona gelen girdiyi temizler.

---

## 2026-08-10 (b) — Monetizasyon kararı "kanıt"tan "hipotez"e indirildi; aylık SKU v1.0'a alındı

**Supersedes:** Aynı gün alınan monetizasyon kararının (aşağıdaki 2026-08-10
kaydı) kesinlik derecesi ve aylık SKU'yu v1.1'e erteleme kısmı. Model
(yıllık-öncelikli abonelik) **değişmedi**; gerekçenin gücü ve kapsam düzeltildi.

**Neden:** Dış inceleme, önceki kaydın dayandığı pazar verisinde üç metodolojik
zayıflık buldu. Üçü de haklı:

1. **Seçim yanlılığı.** RevenueCat bir abonelik altyapısı şirketidir; verisi
   yalnızca **abonelik kullanan** uygulamalardan gelir. Tek seferlik satan
   uygulamalar veri kümesinde yoktur. Dolayısıyla bu veri "seyahatte aboneliği
   nasıl iyi yaparsın" sorusunu cevaplar, **"abonelik gezi-başına modelden iyi
   midir" sorusunu cevaplayamaz.** Önceki kayıt bu veriyi SKU tartışmasını
   kapatan kanıt gibi sundu — hatalıydı.
2. **%66 yıllık endojen bir sayıdır.** Uygulamaların *sattığını* ölçer; çoğu
   seyahat uygulaması yıllığı varsayılan + "en avantajlı" olarak sunduğu için
   kullanıcı tercihi ile paywall tasarımı ayrışmıyor.
3. **Rakiplerde trip-pass olmaması modeli çürütmez.** Kanıtın yokluğu,
   yokluğun kanıtı değildir. Doğru ifade: trip-pass'i *ana model* olarak
   seçmek için pazar kanıtı yok.

**Düzeltilen ifade:** "Abonelik kanıtlandı" → **"abonelik şu anda test
edilmesi en güçlü hipotez."** Rotori lansmanda ₺499/yıl + ₺99/ay modelini
test eder; ilk **100–200 nitelikli kullanıcının** satın alma ve kullanım
verisinden sonra trip-pass, abonelik veya hibrit arasında yeniden
değerlendirilir (yeniden değerlendirme kapısı ve sinyal tablosu:
`MONETIZATION_PLAN.md` §9.2).

**Kapsam değişiklikleri:**

- **Aylık ₺99 v1.0'a alındı** (önceki kayıtta v1.1'e ertelenmişti). Gerekçe
  kapsam değil bilgi: aylık/yıllık dağılımı, kullanıcının Rotori'yi tek-gezi
  aracı mı sürekli hizmet mi gördüğünü söyleyen tek gerçek veri — yani
  trip-pass hipotezini besleyen ölçüm. Deneme **yalnızca yıllıkta**; aylık
  denemesiz düşük-taahhüt seçeneği olarak görünür kalır. Yayın kapsamı
  12–14 → 12.5–15 gün.
- **Kullanıcı görüşmeleri iki dalgaya bölündü.** Dalga 1 yayından önce
  (Faz 1 ile paralel, kod gerektirmez) — amaç dil ve itirazları çıkarmak.
  Dalga 2 yayından sonra gerçek ödeyen kohortu. Görüşmeler **fiyatı
  doğrulamaz**; fiyatı doğrulayan tek veri ödeme ekranındaki davranıştır.
- **"Kazandırdığı saat" göstergesine dürüstlük şartı eklendi.**
  `PlanOptimizationController` infeasible durumlarda yerel kural tabanlı
  fallback preview üretiyor; o yoldan gelen sonuçta kazanç sayısı
  **gösterilmez** (fallback'te matris verisi güvenilir değil). Şişirilmiş bir
  sayı, `af6f721` ve `d0a661f` ile kurulan "bilmediğini uydurmama" ilkesini bozar.
- **SEO stratejisi ayrı belgeye alındı** → `docs/GROWTH_SEO_STRATEGY.md`.
  Ayrıca önceki plandaki **"kullanıcı planlarını otomatik yayımla"** yaklaşımı
  **iptal edildi**: plan verisi tarih/otel/uçuş/kişisel not içeriyor, rıza
  olmadan yayımlanamaz; ayrıca ince-kopya içerik domain'i zayıflatır. Yerine
  editoryal olarak doğrulanmış 20–30 rota sayfası, sonra açık rızayla kullanıcı
  planı yayımlama. Legacy React planner canlandırılmaz; mevcut plan modelinden
  statik sayfa üreten temiz bir hat kurulur.

**Doğrulanamayan ve kullanılmayan iddia:** İncelemede "RevenueCat seyahatte en
büyük iptal nedeninin yetersiz kullanım olduğunu söylüyor" denildi. Kaynakta bu
atıf **bu şekilde yok** — RevenueCat "not using it enough"u gönüllü churn
nedenlerinden biri olarak sayıyor, seyahate özel "en büyük" ataması yapmıyor
(ayrı bir tüketici anketinde genel #1 neden %43 ile maliyet). Bu iddia plana
yazılmadı. Bunun yerine doğrulanan iki sayı eklendi: denemelerin **%82'si
kurulumla aynı gün** başlıyor (→ ön izleme ilk oturumda tamamlanmalı) ve yıllık
aboneliklerin **~%30'u ilk ay içinde iptal ediliyor** (iptal ≠ iade; 1. yıl
geliri korunur ama 2. yıl LTV'si kırılgan).

**Detay:** `docs/MONETIZATION_PLAN.md` (§2.2 uyarı bloğu, §9.1 kanıtın
sınırları, §9.2 yeniden değerlendirme kapısı), `docs/GROWTH_SEO_STRATEGY.md`.

---

## 2026-08-10 — Monetizasyon: yıllık-öncelikli abonelik + kişiselleştirilmiş ön izleme hunisi

**Supersedes:** `docs/CLAUDE.md` §1'deki "ücretsiz reklamsız MVP" yayın hedefi.

**Karar:** Rotori, Pro kapıları takılı olarak yayınlanır. Satış modeli
**yıllık abonelik** (`...japanTrip.pro.yearly`, TR ₺499 / global $29.99,
7 gün ücretsiz deneme). Aylık SKU v1.1'e ertelendi. Tek seferlik satın alma
ve "gezi başına paket" modelleri **reddedildi**.

Ücretsiz taraf: plan oluşturma, ilk günün ön izlemesi + "kazandırdığı saat"
göstergesi, 66 yemeklik rehber, Japonca ifadeler, acil durum bilgileri,
1 aktif gezi, 10 tarama/gün. Dil yardımı ve acil durum bilgisi paywall
arkasına konmaz.

**Neden:** Karar sezgiyle dört kez değişti, sonunda pazar verisine bağlandı
(RevenueCat 2026, 115.000+ uygulama):

- Seyahat aboneliklerinin **%66'sı yıllık** satılıyor — pazar ortalaması %34;
  seyahat tüm kategoriler arasında en yıllık-ağırlıklı kategori. "Gezi tek
  seferlik bir olaydır, abonelik uymaz" sezgisinin pazardaki cevabı bu.
- **Deneme→ödeme dönüşümü %43,5 medyan** (kategoriler arasında en yüksekler).
  Apple'da ücretsiz deneme **yalnızca aboneliklerde** mümkün; tek seferlik
  satın alma bu kolu tamamen kaybediyor.
- Kategorinin **%51,2'si ön izleme *ve* denemeyi birlikte** kullanıyor
  ("mixed trial"). Ön izleme denemenin alternatifi değil, aynı hunide üst
  üste iki adım — 3. turdaki "ön izleme denemeyi gereksiz kılar" varsayımı
  bu veriyle çürüdü.
- Hiçbir başarılı benzer uygulama (TripIt $49/yıl, Wanderlog $29.99–49.99/yıl,
  Tripsy $59.99/yıl, NAVITIME ~¥330/ay) gezi başına satmıyor. Lifetime sunan
  tek örnek (Tripsy $299) onu yıllığın **5 katı** fiyatla çıpa olarak
  konumluyor, ana ürün olarak değil.

**Fiyat:** Seyahat en ucuz kategori (yıllık medyan $20) → TR ₺599 yerine
₺499. Global $29.99 Wanderlog bandında. Fiyat deneyi TR'de değil global $
tarafında yapılır.

**Kayıp / kabul edilen maliyet:** Abonelik, tek seferliğe göre süre yönetimi,
Apple S2S V2 yenileme bildirimleri ve daha katı mağaza uyumu getiriyor
(~3 gün ek iş + sürekli churn yönetimi). Karşılığında ücretsiz deneme hakkı
ve çoklu dönem tahsilatı alınıyor.

**Ayrıca kararlaştırıldı:** Gelirin belirleyicisi fiyat değil dağıtım.
İndirme→ödeme medyanı %2, $1K MRR'a medyan 238 gün, yeni seyahat
uygulamalarının %9,8'i 2 yılda $10K MRR görüyor. Bu yüzden yayın kapsamı
26 günden 12–14 güne indirildi (offline harita paketi, planlama fazı
araçları, bilet kasası, paylaşım, aylık SKU yayın sonrasına ertelendi) ve
dağıtım (video hattı + SEO motoru + affiliate) Faz 1 ile paralel başlatıldı.

**Detay:** `docs/MONETIZATION_PLAN.md` — karar zincirinin tamamı §9'da.

---

## 2026-08-06 — rotori-social deploy kaynağı tek monorepo origin'a birleştirildi

**Supersedes:** rotori-social için ayrı `rotori-social` repository/remote ile
yürüyen deploy pratiği.

**Karar:** rotori-social canlı dağıtım kaynağı artık yalnız
`mennansevim/japan-trip` monorepo `main` branch'idir. Pi5 üzerinde aktif
çalışma ağacı `~/rotori-app/rotori-social` olarak sabitlendi; eski bağımsız
`~/rotori-social` klonu arşivlenip (`~/rotori-social-legacy-<ts>`) aynı yeni
dizine symlink bırakıldı.

**Neden:** Çift repo/çift remote akışı deploy sırasında non-fast-forward ve
senkronizasyon riski üretiyordu. Tek kaynak, tek commit geçmişi ve daha az
operasyonel sürtünme sağlar.

**Etki:**
- Yerelde `social` remote kaldırıldı; tek remote `origin` kaldı.
- Pi üzerinde `git remote -v` artık yalnız monorepo origin'i gösterir.
- Deploy komutları rotori-social alt dizininden (`~/rotori-app/rotori-social`)
  çalıştırılır; eski yol symlink sayesinde kırılmaz.

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
`home_widget`) web build'ine sızmaz.
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

---

## 2026-08-10 — Rota deneyimi refactor'u algoritma-korumalı ilerler

**Karar:** Rota deneyimi refactor'u mevcut yönlü matris, cross-day assignment,
beam search ve hard validator hattını yeniden yazmaz. Varsayılan beam width 6,
hard constraint'ler, must-do/fixed koruması, dört profil ve açık kullanıcı
onayı korunur.

İlk yeni katman, optimizer'ın ürettiği `RouteLeg` verisini skor veya sıra
kararı vermeden kullanıcıya uygun `RouteExecutionLeg` modeline dönüştüren saf
Dart adaptörüdür. Hat/yön ve karmaşıklık gibi matris verileri optimizer
çıktısında kaybedilmeyecek. Kalıcı rota snapshot'ı daha sonra versioned ve
opsiyonel eklenir.

**Neden:** Ürün incelemesinde sorun rota çekirdeğinin kalite kapılarından çok,
üretilen ulaşım bilgisinin viewer'a taşınmaması olarak belirlendi. Çekirdeği
yeniden yazmak mevcut 100 × 4 benchmark güvencesini riske atarken kullanıcı
sorununu doğrudan çözmez.

**Kalite kapısı:** Algoritma davranış sözleşmesi, hedefli domain/controller
testleri ve aynı-seed harness karşılaştırması refactor boyunca zorunludur.
Detay: `docs/ROUTE_EXPERIENCE_REFACTOR_PLAN.md`.

---

## 2026-08-10b — Rota çıktısı versioned snapshot ve dürüst veri güveniyle saklanır

**Karar:** Kullanıcının onayladığı ulaşım ayakları, `DayPlan` içinde opsiyonel
`RouteExecutionSnapshot` schema v1 olarak saklanır. Snapshot plan sürümü,
aktivite hash'i, matris sürümü, profil ve sağlayıcı kimliğini taşır; aktivite
veya zaman çizelgesi değiştiğinde temizlenir. Ön izleme ve viewer aynı
`RouteExecutionLeg` sözleşmesini kullanır.

Tahmini ayaklar `TAHMİNİ` olarak görünür ve hat/yön bilgisi göstermez. Yalnız
reliable sağlayıcı sonucu varsa hat/yön gösterilebilir. UI bekleme alanında
program içi boşluğu değil gerçek transit beklemesini kullanır.

Şehir geçişi modu ve bağlı bilet de ayrı widget mutasyonlarıyla değil,
`PlanScheduleEngine` komutlarıyla atomik biçimde kalıcılaştırılır.

**Neden:** Yalnız aktivite sırası/saatini kaydetmek, kullanıcı planı yeniden
açtığında “nasıl gidileceği” bilgisini kaybettiriyordu. Snapshot optimizer'ın
doğru kaynağı değildir; yalnız doğrulanmış kararın kullanıcıya dönük,
geçersizleştirilebilir sunum kaydıdır. Bu ayrım çekirdek algoritmayı
değiştirmeden saha uygulanabilirliğini artırır.

---

## 2026-08-10c — Erken rezervasyon hatırlatıcıları sonradan ve çoklu eklenebilir

**Karar:** Bilet açılış hatırlatıcıları yalnız plan üretimi sırasındaki otomatik
tespite bağlı değildir. Hatırlatmalar ekranı ve deneyim rehberi aynı ekleme
panelini kullanır. Kullanıcı Shinkansen, Tokyo Disney, USJ ve teamLab hazır
seçimlerinden birden fazlasını seçebilir, her biri için ayrı ziyaret tarihi
belirleyebilir ve serbest başlık/tarih/saatli özel hatırlatıcı ekleyebilir.

Hazır seçimlerde bildirim hesaplanan satış gününde **09:00 cihaz saatinde**
tetiklenir ve bu saat kaydetmeden önce kullanıcıya açıkça gösterilir. Tokyo
Disney ve Shinkansen yayımlanmış kurallar; USJ ve teamLab ise değişebilen satış
takvimleri nedeniyle güvenli planlama hedefleri olarak modellenir. Her preset
resmî doğrulama URL'si taşır; uygulama değişken takvimi kesin tarih gibi sunmaz.

**Sunum:** Deneyim rehberindeki kategori filtreleri kaldırıldı; rehber seçimi
tek yatay şeritte, oyuncak/deneyim ayrıntıları yatay kaydırmalı kartlarda
gösterilir. Yalnız doğrulanmış resmî ve ücretsiz YouTube kanallarına dış
bağlantı verilir. Keşfet menüsünde fiyat etiketi tarayıcı Premium vitrin
kartıdır; mevcut ürün kararındaki ücretsiz 10 tarama/gün ön izlemesi korunur,
Premium değer 100 tarama/gün ve gelişmiş karşılaştırmadır. Rotori Eats küçük
kartlara taşınır ve ücretsiz kalır.

**Algoritma sınırı:** Bu karar yalnız içerik, bildirim ve navigasyon yüzeylerini
değiştirir; yönlü rota matrisi, beam search, hard constraint ve rota snapshot
sözleşmelerine dokunmaz.

---

## 2026-08-10d — Satın alınmış bilet etkinliğe kimlikle bağlanır ve hard constraint olur

**Karar:** Gün içi etkinlik ekleme sırasında kullanıcı “biletim var” dediğinde
bilet ve etkinlik ayrı widget mutasyonlarıyla değil, tek
`AddTicketedActivity` komutuyla eklenir. Mevcut etkinliğe taranan bilet
`AttachTicketToActivity` ile `linkedActivityId` üzerinden bağlanır. Başlık
eşleştirmesi yalnız eski planlar için geriye uyumlu fallback olarak kalır.

Biletin ziyaret tarihi, giriş saati, içeride geçirilecek süre ve erken-varış
payı kalıcıdır. Giriş saati `ticketedEvent` hard constraint'ine dönüşür;
etkinliğin günü/saati/sırası/silinmesi kilitlenir. Bilet tarihi plan içindeki
başka güne denk gelirse etkinlik o güne taşınır ve esnek duraklar sabit
rezervasyonun çevresine yeniden zamanlanır. Rota optimizer'ı etkinlik bazlı
erken-varış payını kendi sabit aktivite tamponuyla `max` alarak uygular.

**Neden:** USJ, Disney ve teamLab gibi tarih/saat bağlı deneyimler rotanın
sonradan eklenen notları değildir; günün geri kalanını belirleyen kısıtlardır.
Yalnız başlığa göre kilitlemek aynı isimli etkinliklerde yanlış bileti
bağlayabilir, bilet ekleme ile plan mutasyonunu ayırmak ise yarım kayıt
üretebilir.

**Sunum:** Gün bazlı “durak ekle” sheet'i bilet anahtarı, süre seçimi ve sabit
saat/erken-varış özetini gösterir. Alt navigasyondaki Keşfet girişi kalıcı bir
ürün yüzeyi olarak korunur ve keşif haritasını açar.

---

## 2026-08-10e — Yeni hatırlatıcı oluşturma Premium'dur; resmî görseller izinsiz kopyalanmaz

**Karar:** Yeni hazır veya özel Rotori hatırlatıcısı oluşturmak Premium
yetkisidir. Kapı tek kaynaktan `premiumProvider` ile uygulanır. Üyeliği sona
eren kullanıcının daha önce oluşturduğu kayıtlar gizlenmez; kullanıcı bunları
görebilir ve silebilir, ancak yeni kayıt oluşturamaz. Gerçek StoreKit/sunucu
entitlement entegrasyonu geldiğinde UI kapıları değişmeden provider kaynağı
yenilenir.

**Görsel kullanımı:** Tokyo Disney Resort ve Universal Studios Japan resmî
site şartları, site materyallerinin ticari uygulamada kopyalanmasına açık izin
vermiyor. teamLab da ticari görsel kullanımı için önceden onay istiyor. Bu
nedenle resmî fotoğraf, karakter, logo veya belirli sanat eseri uygulama asset'i
olarak alınmaz. Hazır seçim kartları Rotori için üretilmiş özgün ve yerel
görseller kullanır; resmî kaynaklar yalnız doğrulama ve dış bağlantıdır.

**Algoritma sınırı:** Değişiklik yalnız entitlement sunumu, hatırlatıcı UI'ı
ve görsel asset'leri kapsar. Rota matrisi, beam search, hard constraint,
validator ve route snapshot davranışı değişmez.

---

## 2026-08-11 — Seyahat çevirisi cihaz-üstü ve iki yönlü konuşma odaklıdır

**Karar:** Japonca sayfası serbest metinde TR/EN ↔ JA çeviriyi Google ML Kit
on-device Translation ile yapar. İki dil modeli yalnız ilk kullanımda açık
kullanıcı aksiyonuyla indirilir; sonrasında çeviri metni cihazdan çıkmaz.
`google_mlkit_translation` mevcut OCR altyapısıyla uyum için 0.13.1 hattında
sabitlenir. Android minimum API 23, iOS minimum 15.5'tir.

Konuşma modu iki düğmeli sırayla çalışan kısa-cümle deneyimidir: Türkçe/İngilizce
konuşma Japoncaya çevrilip Japonca okunur; yön değişince Japonca konuşma yerel
dile çevrilip okunur. Konuşma tanımada `onDevice=true` zorunludur. Telefonda
ilgili offline konuşma paketi yoksa ağ tabanlı fallback yapılmaz; kullanıcıya
paket/izin uyarısı verilir. Sesli çıktı cihazın kurulu sistem sesini kullanır.
Hedef dil sesi dinleme başlamadan doğrulanır. Android'de ağ gerektiren veya
kurulu olmayan TTS sesleri seçilemez; iOS'ta cihazın sunduğu sistem seslerinden
uygun dil seçilir. Hiçbiri yoksa özellik açıkça durur ve bulut sesine düşmez.

**Neden:** Seyahatte en kritik anlar kasada, istasyonda ve restoranda kısa,
karşılıklı cümlelerdir. Sunucu çevirisi ağın zayıf olduğu anda bozulur ve konuşma
metnini dışarı taşır. Cihaz-üstü akış daha öngörülebilir ve gizlidir.

**Sınırlar:** Bu bir insan tercüman değildir; TR ↔ JA çevirisi İngilizceyi ara
dil olarak kullanabildiğinden özellikle sağlık/acil durum cümleleri doğrulanır.
Konuşma modu sürekli dinleme yapmaz ve telefonda kurulu olmayan offline dil
paketini kendisi sağlayamaz. Android 12 (API 31) altındaki yalnız “offline'ı
tercih et” sinyali gizlilik garantisi sayılmaz; bu cihazlarda sesli mod yerine
metin çevirisi sunulur. Web yalnız tasarım ön izlemesidir. Google'ın
zorunlu “Translate with Google”/sonuç atfı korunur.

---

## 2026-08-11b — Hatırlatıcı kart fotoğrafları kullanıcı tarafından seçilecek

**Supersedes:** `2026-08-10e` kaydındaki hazır seçim kartlarının Rotori için
üretilmiş görselleri kullanacağı ayrıntısı. Premium entitlement ve telif
kuralları değişmez.

**Karar:** Otomatik üretilen ilk kart görselleri ürün tonuna uygun bulunmadı
ve nihai asset olarak kullanılmayacak. Kullanıcı Shinkansen, Tokyo Disney,
USJ ve üç teamLab deneyimi için kaynak dosya veya kaynak URL sağlayacak.
Rotori bu dosyaları ancak kendi çekimi, ticari lisanslı stok veya uygulama
kullanımına açıkça izin veren resmî basın kiti olduğu doğrulandığında
yerel WebP asset'e dönüştürecek.

**Geçici sunum:** Kartlar fotoğraf gelene kadar emoji veya taklit marka
görseli yerine düşük doygunluklu gradyan, tutarlı ikon ve sabit okunabilirlik
katmanı kullanır. Fotoğraf takılması entitlement, tarih hesabı veya bildirim
planlama davranışını değiştirmez.

---

## 2026-08-11c — Hatırlatıcı kartları fotoğrafsız, ikon-temelli kalır

**Supersedes:** `2026-08-11b` kaydındaki kullanıcının daha sonra kart
fotoğrafları sağlayacağı ve mevcut sunumun geçici olduğu kararı.

**Karar:** Hazır hatırlatıcı kartlarına fotoğraf eklenmeyecek. Shinkansen,
Tokyo Disney, USJ Express Pass, teamLab Planets, Borderless ve Botanical
Garden seçenekleri birbirinden farklı Material ikonlarıyla temsil edilir.
Sınırlı koyu gradyan paleti, belirgin ikon rozeti ve ortak seçim göstergesi
nihai görsel dil olarak korunur; marka logosu, karakter, emoji veya haricî
görsel asset kullanılmaz.

**Neden:** Küçük kartlarda fotoğraf hem metin okunabilirliğini hem de ürünün
sakin görsel bütünlüğünü zayıflatıyor. İkon-temelli sunum daha hızlı,
çevrimdışı, telif açısından temiz ve altı seçeneği yeterince ayırt edebilir.

**Sınır:** Bu karar yalnız hatırlatıcı kart sunumunu değiştirir. Premium
erişim, satış tarihi hesabı, bildirim planlama ve rota algoritması değişmez.

---

## 2026-08-11d — Cepte Çevirmen premium ve yalnız metindir

**Supersedes:** `2026-08-11` kaydındaki iki yönlü mikrofonlu konuşma ve dinamik
sistem sesi ayrıntıları. Cihaz-üstü metin çevirisi ve Google atfı korunur.

**Karar:** Cepte Çevirmen yalnız TR/EN ↔ JA metin çevirisi sunar. Mikrofon,
konuşma tanıma, sonuç seslendirmesi ve bunların platform izinleri/runtime
bağımlılıkları kaldırılır. Japonca sayfasındaki hazır ifadelerin önceden
paketlenmiş yerel MP3 telaffuzları bu karardan etkilenmez.

Çevirmen `premiumProvider` değerini izler. Ücretsiz kullanıcı en üstte kilitli
premium tanıtımını görür ve dil modeli kontrolü/indirmesi başlamaz. Premium
aktif olduğunda metin alanı, yön değiştirme, model indirme ve çeviri aynı
kartın içinde açılır. Aşağıdaki hazır ifade kategorileri ücretsiz kalır.

**Neden:** İlk App Store sürümünde mikrofon izin ve gerçek-cihaz konuşma paketi
matrisini kapsamdan çıkarmak inceleme riskini azaltır. Metin çevirisi seyahatte
çevrimdışı faydayı korur ve premium değer önerisini netleştirir.

---

## 2026-08-11e — Günlük geçişler her zaman kompakt görünür

**Karar:** Günlük timeline'daki yürüyüş ve ulaşım ayakları çok satırlı kart
yerine ikon, başlangıç→varış, süre ve veri güvenini taşıyan tek satırlık
kompakt yüzey olarak gösterilir. Onaylanmış `RouteExecutionSnapshot` varsa
aynı gerçek/tahmini ayaklar kullanılır. Snapshot yoksa viewer mevcut aktivite
sırasını değiştirmeden yer koordinatlarından geçici tahmini ayaklar türetir;
bu ayaklar kaydedilmez ve `TAHMİNİ` olarak kalır.

**Algoritma sınırı:** İlk planın kural tabanlı hızlı üretimi ile tam rota
optimizasyonu birbirinden ayrıdır. Koordinat tahmini yalnız sunum boşluğunu
doldurur; mevcut sırayı/saatleri değiştirmez ve gösterdiği yaklaşık ulaşım
türünü nihai rota kararı olarak kaydetmez. Kullanıcı “Rotayı optimize et”
dediğinde yönlü matris, beam width 6, hard constraint'ler ve bağımsız validator
çalışır; sonuç yalnız açık onayla kalıcılaşır.

**Neden:** Kullanıcı her durak arasında nasıl geçeceğini ilk açılıştan itibaren
görmek istiyor; büyük kartlar aktivite akışını bastırıyor. Kompakt satır bilgi
sürekliliğini korurken timeline'ın asıl odağını etkinliklerde tutar.

---

## 2026-08-11f — İlk plan kayıt öncesinde gerçek rota motorundan geçer

**Supersedes:** `2026-08-11e` kaydındaki tam beam-search hattının yalnız
“Rotayı optimize et” eyleminde çalışacağı ve kompakt satırların görünür
`TAHMİNİ` metni taşıyacağı ayrıntısı. `2026-08-10b` içindeki veri kalitesi
modeli ve hat/yön uydurmama kuralı korunur.

**Karar:** Kullanıcının “Planı oluştur” eylemi yeni planın ilk rota onayıdır.
Katalog üretimi bittikten sonra normal gezi günlerinin koordinatları ve mekan
çalışma saatleri hazırlanır; yönlü rota matrisi, mevcut beam width 6 optimizer
ve bağımsız validator kayıt öncesinde çalışır. Başarılı sonuç aktivite
sırası/saatleriyle birlikte `RouteExecutionSnapshot` olarak ilk kayda girer.
Mevcut planın daha sonra yeniden optimize edilmesi açık ön izleme/onay akışını
korur. Uçuş, havaalanı/otel transferi ve şehirlerarası sabit geçiş günleri
otomatik yeniden sıralanmaz.

**Canlı veri:** Mobil uygulama sağlayıcı anahtarı taşımaz. Supabase
`route-matrix` Edge Function, sunucu secret'ındaki Google Routes anahtarıyla
yürüyüş, transit ve sürüş matrislerini alıp Rotori'nin sağlayıcıdan bağımsız
modeline normalize eder. Canlı çağrı/cache kullanılamazsa plan kaybolmaz;
koordinat fallback'i ve `estimated` veri kalitesi içeride korunur.

**Sunum:** Kompakt geçiş satırları pembe kart değildir; nötr, zeminsiz tek
satırdır. `TAHMİNİ` kelimesi satırdan kaldırılır. Veri güveni erişilebilirlik
semantiği ve iç modelde kalır; kesin hat/yön bilgisi yalnız güvenilir sağlayıcı
sonucunda gösterilir. Havaalanı transferinin pazarlama/genel açıklaması yerine
hesaplanan varış saati, süre ve havalimanına uygun ulaşım seçenekleri görünür.

**Neden:** Kullanıcı plan oluşturduktan sonra ikinci bir optimizasyon eylemi
aramamalıdır. Güçlü motorun yalnız isteğe bağlı düğmenin arkasında kalması ilk
gösterilen rotayı gereksiz biçimde zayıflatıyordu. Rota sağlayıcısını sunucu
sınırında bağlamak motorun gerçek kapıdan kapıya sürelerle çalışmasını sağlarken
anahtar güvenliğini ve çevrimdışı fallback'i korur.

---

## 2026-08-11g — Crash tanısı ve rota analitiği ayrılır

**Karar:** Teknik crash/hata/performance gözlemi Sentry ile; ürün olayları ve
rota üretim request/result JSON'u Rotori'nin kendi Supabase projesiyle tutulur.
Sentry public DSN ortamdan gelir ve yoksa entegrasyon no-op'tur. Genel olaylar
ile rota fazları cihazdaki kullanıcıya özel outbox üzerinden append-only
gönderilir; ağ/telemetri hatası plan üretimini durdurmaz.

**Veri minimizasyonu:** Analitik rota sözleşmesi tam `Trip.toJson` değildir.
Uçuş, otel, bilet, serbest not, iletişim alanları, fotoğraf, harita URL'si,
gerçek GPS, beslenme tercihi içeriği ve bütçe tutarı dışarıda kalır. Sentry'ye
rota JSON'u, e-posta, ekran görüntüsü veya UI ağacı gönderilmez; yalnız takma
adlı kullanıcı ID'si ve düşük kardinaliteli teknik bağlam eklenir.

**Yetki/silme:** Analitik tablolarda RLS zorunludur; mobil istemci yalnız kendi
satırını ekler ve okuyamaz. Analiz Dashboard/service-role sınırındadır. Hesap
silme Supabase analitik kayıtlarını FK cascade ile temizler. Sentry olayları
proje saklama politikası ve destek üzerinden erken silme talebi kapsamındadır.

**Neden:** Crash tanısı ile ürün optimizasyonunun sorgu ve veri ihtiyaçları
farklıdır. Ayrım, rota verisini üçüncü tarafa taşımadan başarı oranı, süre ve
çıktı kalitesini ölçmeyi; Sentry'nin crash gruplama ve stack trace gücünden de
yararlanmayı sağlar.
