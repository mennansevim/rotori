# CURRENT_TASK.md — Bugünün İşi

> Bu dosya *bugünkü* çalışmanın canlı görünümüdür. Her tamamlanan görevden
> hemen sonra güncellenir.

**Bugünün tarihi:** 2026-08-21
**Aktif branch:** `main`
**Sprint hedefi:** Rota v3 saha gerçekliği katmanını üretim çağrılarına
bağlamak, retry/fallback kaçaklarını kapatmak ve geniş QA ile doğrulamak.

### 2026-08-21 — Viewer drawer tipografi ve başlık hiyerarşisi (tamamlandı)

- [x] Uçuşlar ve Konaklama açılır satırlarının başlık ölçüsünü ortaklaştır.
- [x] KEŞFET altında tekrar eden PLANLAMA ARAÇLARI ve REHBERLER başlıklarını
      kaldır; araç gruplarını tek KEŞFET başlığı altında tut.
- [x] Drawer, otel ve uçuş regresyonlarını çalıştır; hedefli analizi temizle.

**Sonuç:** Uçuşlar satırı artık Konaklama ile aynı ortak açılır başlık
tipografisini kullanıyor. Keşfet alanında yalnızca bir üst başlık kalıyor;
planlama ve rehber listeleri görsel olarak boşlukla ayrılan iki grup halinde
okunuyor. Hedefli drawer/otel/uçuş testleri **18/18** geçti, analiz temiz.

### 2026-08-21 — Faz 1 Tripist-benzeri durak fotoğraf marker'ları (tamamlandı)

- [x] Planlı duraklarda mevcut küratörlü görselleri fotoğraf marker'ı olarak
      kullan; görselleri harita yakınlaşınca görünür kıl.
- [x] Harita pan/zoom sırasında yeni Wikipedia/POI araması başlatma; görsel
      yüklenemezse mevcut numaralı marker'a güvenli biçimde dön.
- [x] OSM/tile altyapısını ve ücretsiz kapsamı koru; etkileşimli tam haritada
      zoom davranışını, hero önizlemesinde sakin başlangıç görünümünü doğrula.
- [x] İlgili viewer harita testlerini ve hedefli analizi çalıştır.

**Sonuç:** `RouteMapSheet` ve Harita hero'sundaki planlı duraklar zoom 15 ve
üzerinde mevcut küratörlü görseli, daha uzak ölçekte ise mevcut numaralı pin ve
etiketi gösteriyor. Görsel yüklenemezse pin görünümü korunuyor. Yeni POI API'si,
backend veya tile ön-indirmesi eklenmedi. Hedefli analiz temiz; viewer harita,
görsel resolver ve rehber testleri **40/40** geçti. Wikimedia görselleri için
dosya bazlı yazar/lisans atıf envanteri release öncesi açık iştir.

### 2026-08-21 — Web logosunu mobil kaynağıyla eşitleme (tamamlandı)

- [x] Mobilde kullanılan `rotori-logo.png` dosyasını web asset'lerine ekle.
- [x] Ana site, App Preview, destek ve gizlilik sayfalarındaki görünür marka
      işaretlerini aynı logo kaynağına bağla.
- [x] Favicon ve PWA ikon varyantlarını tarayıcı uyumluluğu için koru.

**Sonuç:** `rotori-mobile/assets/images/rotori-logo.png` ile web'deki görünür
logo kullanımları birebir eşitlendi. Yeni web asset'i kaynak dosyayla aynı
SHA-1 değerini taşıyor.

### 2026-08-19 — Günlük hava aksiyonu ve yağmur sıralaması (tamamlandı)

- [x] Gün kartlarındaki “Rotayı optimize et” aksiyonunu “Havaya göre düzenle”
      olarak değiştir; premium kilidini bu bağlamdan kaldır.
- [x] Her günün altında mevcut güvenli rota önizleme/onay akışını hava aksiyonu
      üzerinden erişilebilir tut.
- [x] Hava aksiyonu için viewer regresyon testi ve hedefli analiz çalıştır.
- [x] Yağışlı/sert hava günlerinde kapalı mekânları öne, açık hava duraklarını
      sona alan kararlı kategori sınıflandırması üret; katalog placeId
      kategorilerini ve metin sinyallerini birlikte kullan.
- [x] Hava sırasını rota motoruna soft order hint olarak geçir; saatli ve
      kilitli durakların hard constraint davranışını koru.

**Sonuç:** Her gün kartındaki rota aksiyonu artık “Havaya göre düzenle” olarak
görünüyor. Yağmur/sert hava tespitinde müze, akvaryum, alışveriş, restoran ve
benzeri kapalı mekânlar öne; park, bahçe, doğa ve açık hava durakları sona
alınıyor. Rota motoru ulaşım/açılış saatlerini yeniden doğruluyor; saatli ve
kilitli duraklar korunuyor, plan yalnız kullanıcı onayıyla değişiyor. İlgili
domain/controller/viewer/weather testleri geçti ve hedefli analiz temiz.


### 2026-08-18 — Preview auth akışlarını çalıştırma (tamamlandı)

- [x] Preview'da Supabase başlatılmadığı halde production auth repository'sine
      giden Google, Apple ve kayıt aksiyonlarını yerel preview repository'sine
      bağla.
- [x] Başarılı preview auth işlemlerini demo planlarına döndüren callback ekle;
      production auth state yönlendirmesini değiştirme.
- [x] Apple butonundaki web font karakterini gerçek Apple ikonuyla değiştir;
      preview auth testleri, analiz ve canlı 390×844 akışıyla doğrula.

**Sonuç:** Preview auth ekranı artık Supabase istemcisi istemiyor. Google,
Apple ve e-posta/şifre kayıt aksiyonları yerel preview repository'siyle
başarılı olup `/plans` demo ekranına dönüyor. Apple ikonu web'de görünür hale
geldi. Canlı preview'da üç akış da doğrulandı; auth testleri **12/12**, hedefli
analiz temiz.

### 2026-08-18 — Preview çıkış ve auth akışları (tamamlandı)

- [x] Drawer'da “Çıkış yap” satırını misafir/preview kullanıcıda da göster;
      dokununca login ekranına yönlendir, gerçek oturumda sign-out yapıp aynı
      hedefe geç.
- [x] Google ile giriş butonunun OAuth çağrısını ve kayıt modunun
      `signUpWithPassword` çağrısını widget testleriyle doğrula.
- [x] Çıkış satırının görünürlüğü ve login rotasına geçişi için drawer
      regresyonu ekle; hedefli test ve analizi çalıştır.

**Sonuç:** Preview drawer artık “Çıkış yap” satırını saklamıyor. Satır misafir
kullanıcıyı doğrudan login rotasına götürüyor; giriş yapılmış kullanıcıda önce
Supabase oturumu kapatılıyor, ardından aynı login rotası açılıyor. Google OAuth
ve e-posta/şifreyle kayıt hareketleri widget testleriyle doğrulandı.

### 2026-08-18 — Rehber hazırlık kartını kaldırma (tamamlandı)

- [x] “Seyahat öncesi hallet” kartını Rehber konu listesi ve konu detayından
      kaldır; Keşfet menüsündeki ayrı erişimi koru.
- [x] Kartın Rehber'e geri eklenmesini yakalayan widget regresyonu ekle.

**Sonuç:** Hazırlık kartı ve yalnız bu karta hizmet eden Rehber içi affiliate
bileşeni kaldırıldı. Hazırlık akışının Keşfet menüsündeki girişi korunuyor.
Rehber + drawer hedefli testleri **20/20** geçti, targeted analyze temiz,
release web derlemesi başarılı ve Rehber listesinin sonu canlı preview'da
görsel olarak doğrulandı.

### 2026-08-18 — Rehber detay geçiş izi (tamamlandı)

- [x] Videodaki hayalet izi üreten liste–detay cross-fade katmanını kaldır.
- [x] Detayı sağdan, konu listesini soldan tam ekran genişliğinde ve kırpılmış
      panel geçişleriyle aç; geri dönüşte yönleri tersine çevir.
- [x] Geçişin ilk ve ara karelerini widget regresyonuyla; analiz, release web
      derlemesi ve canlı preview akışıyla doğrula.

**Sonuç:** Rehber sekmesindeki `AnimatedSwitcher` artık iki tam sayfayı
cross-fade etmiyor. `ClipRect` içindeki anahtarlı tam genişlik geçişinde liste
sola çıkarken detay sağdan geliyor; geri dönüşte hareket aynalanıyor. Böylece
videoda görülen yarı saydam metin izi ortadan kalkıyor. Rehber + drawer hedefli
testleri **20/20** geçti, targeted analyze temiz, release web derlemesi başarılı
ve güncel Rehber → Para ve Ödeme akışı canlı preview'da açıldı.

### 2026-08-18 — Premium uyarı standardı (tamamlandı)

- [x] Tasarım seçici, rota optimizasyonu, hatırlatıcı ve fiyat etiketi
      tarayıcı premium uyarılarını tek ortak bileşene bağla.
- [x] Tüm premium sheet'lerde mor gradyan, altın madalyon, bağlama özel fayda
      listesi ve sarı “Anladım” aksiyonunu standartlaştır.
- [x] TR/EN metinleri, büyük yazıda kaydırma ve telefon görünümünü doğrula.

**Sonuç:** Dört ayrı premium uyarısı `RotoriPremiumSheet` üzerinden aynı
mor–altın görsel dili kullanıyor. Mevcut ekranlara özgü başlık, açıklama ve
faydalar korunurken kapatma davranışı ve erişilebilir yerleşim ortaklaştı.
Ortak bileşen, hatırlatıcı, fiyat tarayıcı ve viewer testleri başarılı;
hedefli analiz temiz, release web derlemesi tamamlandı ve 390×844 ön izlemede
tasarım seçici premium uyarısı taşmasız doğrulandı.

### 2026-08-18 — Aktivite detayından ortak bilet ekleme (tamamlandı)

- [x] Yer detayındaki “Bilet ekle” aksiyonunu ayrı kamera/galeri menüsünden
      çıkarıp kalıcı alt menüdeki Biletler sekmesine bağla.
- [x] Bilet cüzdanındaki ortak fotoğraf, kamera ve manuel ekleme panelini
      aktivite bağlamıyla yeniden kullan; seçili aktivitede “Plandan seç”
      tekrarını gösterme.
- [x] Kaydedilen bileti `AttachTicketToActivity` ile seçili aktiviteye bağla;
      eski doğrudan içe aktarma çağrılarını geriye uyumlu tut.

**Sonuç:** Aktivite detayındaki CTA önce detay sheet'ini kapatıyor, Biletler
sekmesine geçiyor ve ortak bilet ekleme panelini açıyor. Alt menü aynı viewer
shell içinde sabit kalıyor. İlgili widget paketleri **65/65** geçti, hedefli
analiz temiz, release web preview derlendi ve Tokyo Disneyland akışı açık
önizlemede konsol hatası olmadan doğrulandı.

### 2026-08-18 — Rehber sekmesi yeniden tasarımı (tamamlandı)

- [x] Rehber'i büyük başlık, geziye bağlı açıklama ve tüm konularda çalışan
      arama alanıyla yeniden düzenle.
- [x] Acil Durum, Suica, Para ve İnternet için Hızlı erişim alanı ile tek
      inset-group konu listesini; ikon, madde sayısı ve chevron hiyerarşisini
      ekle.
- [x] Konu detayını aynı Rehber sekmesinde geri düğmesiyle aç; üst durum
      çubuğu ve sabit alt menüyü koru.

**Sonuç:** Rehber büyük başlık, arama, Hızlı erişim ve inset konu listesiyle
yenilendi; detay görünümü aynı sekmede açılıyor ve persistent shell korunuyor.
Hedefli viewer testleri **67/67** geçti, targeted analyze **0 issue** verdi ve
`flutter build web --release -t lib/preview_main.dart` başarılı oldu.
390×844 web ön izlemesinde liste/detay taşmasız ve sabit alt menüyle görsel
doğrulandı.

### 2026-08-18 — Auth ve preview hesap aksiyonları (tamamlandı)

- [x] Google giriş butonundaki tekrar eden `G` metnini kaldır; görünen ifade
      yalnızca “Google ile Giriş Yap” olsun.
- [x] Apple ile girişi iOS/macOS native akışında koru, web'de Supabase OAuth
      akışını da göster; Google OAuth açılışını platform varsayılanına taşı.
- [x] Preview'daki Misafir satırını pasif durum bilgisi yap; oturumsuz
      kullanıcıya çalışmayan Çıkış yap aksiyonu gösterme.
- [x] Auth etiketi, Apple görünürlüğü ve Misafir davranışı için regresyon testi
      ekle; hedefli analiz ve release web derlemesini çalıştır.

**Sonuç:** Auth ekranındaki Google etiketi düzeltildi. Apple butonu iOS/macOS'ta
nonce doğrulamalı native akışı, web'de Supabase OAuth'u kullanıyor. Preview'da
Misafir satırı drawer'ı kapatıp auth ekranına göndermiyor; Çıkış yap yalnızca
gerçek oturumda gösteriliyor. Auth/drawer hedefli testleri ve değişen dosya
analizi başarılı; güncel release web preview `rotori-mobile/build/web` altında
üretildi. Drawer test paketinde önceki tasarım değişikliklerinden kalan 6→8
ikon beklentisi ayrı tutuldu.

### 2026-08-17 — Ödül kutlaması ve drawer yerleşimi (tamamlandı)

- [x] Rütbe ödülü penceresini örnekteki koyu cam yüzey, madalyon, sıcak altın
      vurgu ve tek “Devam” aksiyonuyla yenile; metinlerde alt çizgi kullanma.
- [x] “Tasarımı değiştir” ve “Seyahat öncesi hallet” satırlarını Keşfet
      başlığının altındaki gruba taşı; Hesap bölümünü yalnız hesap/uygulama
      aksiyonlarıyla bırak.
- [x] Türkçe ve İngilizce yardımcı metinleri ekle; drawer yerleşim testini yeni
      bilgi mimarisine göre güncelle.

**Sonuç:** Rütbe atlama penceresi referanstaki koyu, odaklı ödül yüzeyine
yaklaştırıldı; madalyon üstte taşan sıcak ruby/altın görünümde, başlıklar ve
CTA alt çizgisiz. Tasarım ve seyahat öncesi satırları Keşfet grubunun ilk iki
öğesi olarak gösteriliyor. Analiz temiz, hedefli drawer senaryosu başarılı.

### 2026-08-17 — Tasarım seçici kompakt ve erişilebilir sheet (tamamlandı)

- [x] Tasarım seçiciyi telefon yüksekliğine uyumlu, en fazla %90 ekran
      yüksekliğinde ve içerik kaydırılabilir olacak şekilde düzenle.
- [x] Tasarım önizlemelerini, tema seçeneklerini ve dil butonlarını daha
      kompakt ölçülere indir; “Bitir” düğmesini alt alanda sabit tut.

**Sonuç:** Tasarım sheet'i artık içerik uzadığında yalnızca gövdeyi kaydırıyor;
“Bitir” düğmesi her ekran yüksekliğinde görünür kalıyor. Önizleme kartı 184 dp,
seçim satırları ve kapatma düğmesi daha dengeli dokunma alanlarıyla gösteriliyor.
Widget testi, statik analiz ve release web önizlemesi başarılı.

### 2026-08-17 — Uçuş kartı responsive son cilası (tamamlandı)

- [x] Rota çizgisini sabit dar merkez kutusu yerine üç sütunlu akışın tamamına
      yay; uçak ikonunu çizginin gerçek merkezine al.
- [x] Varış bilgisini referanstaki şehir → IATA sırasına taşı; dar ekranda
      şehir adlarının gereksiz kırpılmasını önle.
- [x] Üst etiket, tarih, IATA rozeti ve iç girintileri referans yoğunluğuna
      getir; TR/EN, aktarma ve gün aşımı davranışını koru.

**Sonuç:** Drawer uçuş kartı 390 dp ön izlemede referans kompozisyonuna
yaklaştırıldı. Noktalı rota iki yandan görünür, şehir/IATA hiyerarşisi iki
uçta tutarlı ve kart içi yatay boşluklar dar ekranda taşmasız. Hedefli viewer
widget paketi **48/48** geçti; Flutter web release ön izlemesi görsel olarak
doğrulandı.

### 2026-08-17 — Uçuşlar bölümü kompaktlaştırma (tamamlandı)

- [x] Uçuş akordiyonunu ve iki uçuş kartını yaklaşık %40 daha küçük görsel
      yoğunluğa indir; başlık, etiket, tarih, saat ve rota metriklerini birlikte
      ölçekle.
- [x] Kartlar küçülürken şehir/IATA, aktarma, süre ve gün aşımı bilgisini
      koru; uçuş akordiyonunda 44 dp dokunma alanını koru.

**Sonuç:** Uçuşlar bölümü dar ön izlemede daha az dikey alan kaplıyor; saatler,
etiketler ve rota detayları yaklaşık %40 küçültüldü. Otel akordiyonu genel
kabuk davranışını koruyor. Viewer widget paketi ve dosya analizi başarılı;
390 dp release web ön izlemesi görsel olarak doğrulandı.

### 2026-08-17 — Journey hero ve premium tasarım seçici (tamamlandı)

- [x] Yolculuk hero'sunda `journey-progress-hero.webp` görselini düşük
      opaklıklı, ortalanmış arka plan olarak kullan.
- [x] Tasarım değiştir sheet'ini yatay kaydırılan, gerçek görsel önizlemeli
      kartlara taşı; seçili tasarımı ve dokunma alanlarını okunaklı koru.
- [x] Rota Panoraması'nı ücretsiz varsayılan bırak; Yolculuk ve Harita'yı
      premium kilidi ve standart bilgilendirme sheet'iyle sınırla.

**Sonuç:** Yeni kurulum Rota Panoraması ile açılıyor. Tasarım sheet'i yatay
önizleme kartlarında seçili durumu, iki premium kilidini ve premium
bilgilendirmesini gösteriyor. Yolculuk hero'su yerel görseli %100 opaklıkta
merkezli arka plan olarak kullanıyor; ilerleme halkası ve metinler okunaklı
kalıyor. İlgili viewer widget testleri **54/54** geçti, hedefli `flutter
analyze --no-pub` temiz ve release web önizlemesi görsel olarak doğrulandı.

### 2026-08-17 — Panorama, uçuş, harita ve otel tasarımı (tamamlandı)

- [x] Aktif şehir fotoğrafını Yolculuk hero'sundan kaldırıp Rota Panoraması
      kartına düşük opaklıklı, merkezlenmiş arka plan olarak taşı.
- [x] Panorama kartının dış ve iç yatay boşluklarını dar telefonlarda dengeli
      ve taşmasız hale getir.
- [x] Drawer uçuş kartını referanstaki üç sütunlu saat–rota–saat düzenine taşı;
      şehir/IATA ve gün aşımı bilgisinin saate binmesini engelle.
- [x] Harita hero'sunu yaklaşık %10, Sıradaki kartını yaklaşık %15 küçült;
      tarih kartlarını daha sade ve okunabilir Apple hiyerarşisine taşı.
- [x] Otel ekleme formundaki kişisel örnek/metinleri tamamen temizle; ücretsiz
      Google Maps araması açan yönlendirmeyi ve tek sütunlu telefon düzenini ekle.
- [x] Hedefli widget testleri, analiz ve tarayıcı önizlemesiyle iki kez doğrula.

**Sonuç:** Şehir fotoğrafı yalnız Rota Panoraması kartında %12,6 opaklıkla,
merkezlenmiş ve karta kırpılmış olarak gösteriliyor; Yolculuk yeniden sakin
çizgi desenini kullanıyor. Uçuş kartı üç sütunlu ve dar ekranda taşmasız;
gün aşımı saatten ayrıldı. Harita 241–270 dp aralığına, Sıradaki kartı yaklaşık
%15 daha küçük kompozisyona çekildi; tarih şeridi nötrleştirildi. Otel formu
boş açılıyor, kişisel örnek içermiyor ve ücretsiz Google Maps araması sunuyor.
İlgili widget paketleri iki turda **49/49**, tüm Flutter test paketi
**1083/1083** başarılı; tam `flutter analyze` temiz ve tarayıcı önizlemesiyle
görsel kontrol tamamlandı.

---

### 2026-08-17 — Uçuş kartı referans görseli (tamamlandı)

- [x] Drawer içindeki uçuş kartını referanstaki gezi etiketi, tarih, büyük saat,
      noktalı rota ve şehir/IATA düzenine taşı.
- [x] Gidiş-dönüş, aktarma ve gün aşımı gösterimlerini koru; TR/EN ve dar
      telefon görünümünü widget testleriyle doğrula.

**Sonuç:** Drawer uçuş kartları referanstaki kompozisyona taşındı: `GEZİ/TRIP`
etiketi ve tarih üst satıra, büyük saatler noktalı rota/uçak ikonunun iki yanına,
şehir adları ayrı IATA rozetlerine alındı. Uçuş süresi, aktarma bilgisi ve gece
varışında `+1` korunuyor. Hedefli analiz temiz; viewer regresyonları **46/46**
başarılı.

---

## 🚦 SIRADAKİ OTURUM BURADAN BAŞLAR

**Aktif yayın takibi:** `docs/TESTFLIGHT_READINESS.md`

### 2026-08-18 — Planlarım kartlarında şehir rotası görünümü (tamamlandı)

- [x] Plan kartlarını şehir hero görseli ve referans kart hiyerarşisine taşı.
- [x] Çok şehirli planlarda şehirleri rota sırasıyla, ülke adıyla birlikte göster.
- [x] Tarih aralığı, gün sayısı ve şehir sayısını TR/EN yerelleştir.
- [x] Düzenle/sil aksiyonlarını kartın üst menüsünde koru; şehir sunum yardımcılarını test et.

**Sonuç:** Planlarım ekranındaki düz satır kartlar, yerel şehir görseli,
başlık, şehir rotası, kısa tarih aralığı, gün rozeti ve şehir rozeti taşıyan
referans görünümlü kartlara dönüştürüldü. Şehirler plan verisindeki rota sırasına
göre tekilleştirilerek gösteriliyor; analiz ve plan sunum testleri başarılı.

Bir sonraki oturumda bu dosyanın **P0 / 1. Apple imzalama** bölümündeki ilk
işaretlenmemiş maddeden devam edilir. Tamamlanan her madde kanıtıyla birlikte
orada işaretlenir; bu dosyada ayrıca paralel bir checklist tutulmaz.

### 2026-08-16 — Şehir bazlı sabit hero görseli (tamamlandı)

- [x] Plan oluştur kataloğundaki 21 şehir için yerel, özgür lisanslı Commons
      hero görsellerini WebP asset olarak ekle.
- [x] Yolculuk tasarımındaki üst görseli aktif destinasyon şehrine bağla.
- [x] Görseli sabit tutup ilerleme/sıradaki aktivite ve gün akışını üzerine
      kaydır; hedefli analiz ve viewer widget testini çalıştır.

**Sonuç:** Tokyo’dan Okinawa’ya tüm şehirler için `city-hero-*.webp` asset’leri
paketlendi. Yolculuk tasarımında günün destinasyonu değişince hero da değişiyor;
şehir görseli sabit kalırken altındaki kart yüzeyi ve rota akışı üstüne kayıyor.
Hedefli `flutter analyze` temiz, viewer test paketi **46/46** başarılı.

### 2026-08-14 — TestFlight kod hazırlığı ve harita politika düzeltmesi (tamamlandı)

- [x] Production auth ekranından gömülü demo e-posta/parolayı kaldır.
- [x] Privacy Manifest'i güncelle ve Runner resource paketine bağla.
- [x] Sign in with Apple entitlement'ını bütün Runner build ayarlarına bağla;
      TR/EN `InfoPlist.strings` permission metinlerini ekle.
- [x] Premium butonlarını ve mevcut Pro bilgilendirme akışını koru.
- [x] Google/CARTO raster endpoint'lerini standart OSM katmanına taşı; toplu
      ön-indirme, disk cache ve `flutter_cache_manager` bağımlılığını kaldır.
- [x] OSM attribution'ını telif sayfasına bağla ve analiz borcunu temizle.

**Sonuç:** Uygulama içi harita online çalışmayı koruyor ancak artık kalıcı
offline tile paketi vaat etmiyor. Plan/veri snapshot'larının çevrimdışı
davranışı değişmedi. Apple hesabı, provisioning profile, Supabase production
ve App Store Connect üzerinde dış değişiklik yapılmadı. Flutter analyze temiz,
tam Flutter test paketi başarılı. Temiz `--release --no-codesign` iOS build'i
132,7 MB `Runner.app` üretti; uygulamanın kendi `PrivacyInfo.xcprivacy` dosyası
ile `en.lproj`/`tr.lproj` permission metinleri paket içinde doğrulandı.

### 2026-08-14 — Viewer'da iki tasarım arasında geçiş (tamamlandı)

- [x] “Yolculuk” görünümünde ilerleme özeti ile sıradaki aktiviteyi öne çıkar.
- [x] “Harita” görünümünde seçili tek günün raster yol haritası katmanını,
      numaralı GPS duraklarını ve rota çizgisini planın üstüne taşı.
- [x] Tarih çipini tek aktif gün kaynağı yap; harita ile aşağıdaki rota
      içeriğini birlikte değiştir ve diğer günleri bu görünümde çizme.
- [x] Harita görünümünde düzenlemeyi de seçili güne kilitle; haritayı görünür
      tut ve tarih sekmelerini ikonsuz, kompakt, renkli hale getir.
- [x] Harita tarih şeridindeki tüm günleri telefon genişliğine kaydırmasız
      sığdır; Yolculuk hero'sunu çizimli Japonya ve parçalı ilerleme tasarımına
      yaklaştır.
- [x] Drawer'daki “Tasarımı değiştir” seçimini cihazda kalıcı, tema seçiminden
      bağımsız ve plan verisini değiştirmeyen tekli seçim olarak uygula.

**Sonuç:** Kullanıcı aynı seyahat planını Yolculuk veya Harita tasarımıyla
görüntüleyebiliyor; seçim uygulama yeniden açıldığında korunuyor. Eski/geçici
ayar anahtarları güvenli biçimde yeni iki tasarıma taşınıyor, bilinmeyen değerler
Yolculuk görünümüne dönüyor. Harita görünümünde 28→29→30 canlı geçişi üç ayrı
ekran görüntüsüyle doğrulandı; her seçim yalnız ilgili günün haritasını ve rota
kartını gösteriyor. OSM yol haritası tam genişlikte, tarih şeridi haritanın
içinde; beyaz halolu mavi rota, dönüşümlü yer etiketli pembe GPS pinleri ve
beyaz tek-gün paneli referans görselin hiyerarşisine getirildi. Rota çizgisi
son görsel turda 3 px sabit mavi çizgi ve 5,5 px ince beyaz halo olarak
zarifleştirildi; kırmızı numaralı noktalar 36 px'ten 28 px'e indirildi.
Tarih sekmeleri ikonsuz, daha renkli ve telefon genişliğine eşit paylaşılan
kaydırmasız bir şeride dönüştürüldü. Harita düzenleme modu haritayı koruyup
yalnız seçili günü düzenliyor. Yolculuk üst alanı Tokyo kulesi/uçak ile
Fuji/pagoda/sakura çizimlerini, dört parçalı ilerleme halkasını ve referanstaki
mavi “Sıradaki” kartını kullanıyor.
Tasarım seçici, kalıcılık ve viewer regresyonları testlerle kapsandı; hedefli
analiz temiz, tam Flutter paketi **1.078/1.078** başarılı. Daha sonra yapılan
TestFlight hazırlığında fiyat etiketi tarayıcı ve bağımsız test lint'leri de
temizlendi.

### 2026-08-14 — Hibrit LLM rota iyileştirme ve motor benchmarkı (tamamlandı)

- [x] LLM'i doğrudan plan mutasyonu yerine mevcut duraklar için sıra adayı
      üreticisine çevir; strict şema, karmaşık gün kapısı, timeout ve cache ekle.
- [x] Adayı yalnız etkilenen günlerde yumuşak beam ipucuyla yeniden optimize et;
      snapshot, aktivite kümesi ve en az %2 objective iyileşmesiyle kabul et.
- [x] Saha transit değerlemesini istek ömründe memoize et ve 100×4 aynı-seed
      benchmarkıyla hız/kalite farkını ölç.

**Sonuç:** Beam 6 korunarak 100 base × 4 profil koşusunun medyanı
**28.740 ms → 16.854 ms** oldu (**%41,4 hızlanma**). 4.672 gün kaydı,
3.668 strict gün, dropping ile kurtarılan 464 gün, 472/17.700 düşürülen
aktivite, 0 infeasible, 0 hard ihlal, 0 must-do kaybı ve 0 eksik dönüş dahil
semantik çıktı önceki koşuyla birebir aynı kaldı. LLM yolu `gpt-4o-mini`
strict Structured Outputs kullanır; en fazla üç karmaşık günü çağırır, 6 sn
sunucu/8 sn istemci üst sınırı ve 7 günlük bellek cache'i taşır. Aday ancak
yeniden üretilmiş snapshot ile gerçek objective skoru en az %2 iyileştirirse
kabul edilir; tüm diğer durumlarda deterministik plan korunur. Son tam Flutter
paketi **1.064/1.064** geçti, hedefli analiz temiz. Son teyit benchmarkı
16.300 ms verdi ve önceki çıktıyla semantik karşılaştırma yine birebir eşleşti.

### 2026-08-14 — R harfinden türeyen Rotori reklam animasyonu (tamamlandı)

- [x] Rotori işaretini kırmızı rota çizgisinden kuran özgün açılış hareketini
      ve ekranları tekrar işarete toplayan kapanışı tasarla.
- [x] Şehir seçimi, gün planı, ayrıntılı timeline ve bütçe ekranlarını sakin,
      beyaz boşluk ağırlıklı 9:16 reklam akışına bağla.
- [x] Telifsiz sentetik ses tasarımını ekle; H.264/AAC medya özelliklerini,
      geçiş karelerini, okunabilirliği ve final posterini doğrula.

**Sonuç:** `rotori-social/scripts/create_rotori_r_ad.py` aynı reklamı yerel
asset'lerden tekrar üretebiliyor. Nihai çıktı 1080×1920, 30 fps, 12,6 saniye,
H.264 + AAC ve yaklaşık 3 MB olarak
`rotori-social/output/reels/rotori_r_apple_ad_1080x1920.mp4` altında hazırlandı.
Altı kritik kare ve yarım saniyelik hareket matrisi görsel olarak kontrol
edildi; başlık geçişlerindeki üst üste binme giderildi.

### 2026-08-14 — Drawer Tema/Hesap hiyerarşisi (tamamlandı)

- [x] Tek öğeli Araçlar bölümünü, başlığını ve ayrı kartını kaldır.
- [x] Tema seçiciyi Hesap bölümündeki ayar grubunun ilk satırına taşı.
- [x] Tema seçici davranışını, yeni bölüm sırasını ve dar telefon görünümünü
      regresyonlarla doğrula.

**Sonuç:** Drawer artık Yolculuk → Keşfet → Hesap hiyerarşisini kullanıyor.
Tema, Misafir/profil kartının altındaki hesap ayar grubunda yer alıyor;
Araçlar başlığı görünmüyor. İlgili drawer/viewer regresyonları **41/41**
başarılı, hedefli analiz temiz; iPhone 15 Pro ön izlemesinde alt bölüm
görsel olarak doğrulandı.

### 2026-08-13 — Eğlence rehberi görsel sadeleştirmesi (tamamlandı)

- [x] Seçili deneyim, rehber özeti, Premium hatırlatıcı ve resmî video
      alanlarındaki geniş kırmızı/mor gradyan yüzeyleri kaldır.
- [x] Uyarı, ipucu, akış ve strateji kartlarını viewer'ın beyaz/dark nötr
      kart sistemi ile tek ana vurgu rengine taşı.
- [x] Deneyim seçimi, hatırlatıcı, resmî bağlantılar ve yatay kart davranışını
      koru; dar telefon görünümünü ve regresyonları doğrula.

**Sonuç:** Hero görseli sayfanın tek güçlü görsel yüzeyi olarak korundu;
gövde kartları tema uyumlu nötr yüzey, ince kenarlık ve mavi ana vurgu ile
drawer'ın genel diline yaklaştırıldı. Renk artık seçili durum, küçük ikon ve
ana aksiyonlarla sınırlı. 390×844 iPhone ön izlemesinde üst, orta ve alt
kaydırma konumları taşmasız doğrulandı. Eğlence rehberi regresyonları **6/6**
başarılı; hedefli analiz temiz.

### 2026-08-13 — Viewer drawer referans tasarım cilası (tamamlandı)

- [x] Keşfet satırlarında ikon tonlarını mor, mavi, turuncu, yeşil, turkuaz
      ve pembe olarak ayrıştır; ortak sakin inset-group yüzeyini koru.
- [x] Misafir hesabını pembe vurgulu, oturum açmaya yönlendiren profil
      satırına dönüştür; hesap aksiyonlarında işlevsel renk hiyerarşisi kur.
- [x] “Çıkış yap” aksiyonunu ana hesap grubundan ayırıp pembe uyarı yüzeyine
      taşı; dar ekran ve regresyon kontrollerini tamamla.

**Sonuç:** Referans görseldeki üst hero, üçlü gezi özeti, uçuş/konaklama ve
tek-gruplu Keşfet yapısı korunarak alt bölümün renk ve hesap hiyerarşisi
tamamlandı. iPhone 390×844 web ön izlemesinde üst/alt kaydırma konumları
görsel doğrulandı. Drawer, özet ve viewer regresyonları **41/41** başarılı;
hedefli analiz temiz.

### 2026-08-12 — Viewer drawer görsel bütünlük turu (tamamlandı)

- [x] Yolculuk ve Hesap bölümlerindeki sakin inset-group dilini Keşfet ve
      Araçlar dahil panelin tamamına uygula.
- [x] Keşfet'teki iki gradyan vitrin ile 2×2 renkli kart ızgarasını tek,
      okunabilir aksiyon grubuna indir; bütün davranış ve Premium durumunu
      koru.
- [x] TR/EN, küçük ekran, dark tema, widget regresyonları ve analizle doğrula.

**Sonuç:** Hero ve Yolculuk bilgi yapısı korunurken drawer'ın bütün alt yüzeyi
18 px köşe yarıçaplı, ince kenarlıklı beyaz/dark inset-group sistemine alındı.
Fiyat etiketi tarayıcı, macera rehberi, hava, bütçe, checklist ve Rotori Eats
tek altı satırlı grupta birleşti; gradyanlar, büyük gölgeler, 2×2 karo düzeni
ve kuzeydoğu okları kaldırıldı. Premium durumu küçük rozetle korunuyor.
Hedefli analiz temiz; drawer, yolculuk özeti ve viewer regresyonları **37/37**
başarılı. 390×844 iPhone ön izlemesinde açık ve Japon Gecesi temalarında üst,
orta ve alt scroll konumları görsel olarak doğrulandı; yeni taşma veya konsol
hatası yok.

### 2026-08-12 — Rota v3 üretim entegrasyonu ve bakım doğrulaması (tamamlandı)

- [x] `FieldRealityContext` üretim controller'ında tarih, şehir, parti, pass,
      bagaj, kapanış ve tekrar sinyallerinden kurulsun; retry/dropping boyunca
      kaybolmasın.
- [x] Field hard kapılarını atlayan yerel fallback'i kapat; bağımsız validator
      saha-düzeltilmiş transit ve kapanış kurallarını yeniden doğrulasın.
- [x] Plan köküne `schemaVersion: 3`, Japonca büyük istasyon alias'ları ve
      hafta sonu/resmî tatil trafik katsayısı ekle.
- [x] 100×4 optimizer QA'sını gerçek field bağlamıyla çalıştır; tam gün tema
      parkı sürelerinde kuyrukların iki kez sayılmasını ve must-do öncelik
      kaybını gider.

**Sonuç:** Üretim ve harness isteklerinin tamamı saha bağlamlıdır. 100 base ×
4 profil koşusunda **4.252 gün / 3.748 optimizer günü / 16.120 aktivite**
incelendi: 0 infeasible, 0 hard ihlal, 0 ardışık tekrar, 0 must-do kaybı,
0 eksik dönüş; bırakma oranı **%2,58** ile %3 kapısının altında. Gerçek üretim
QA'sı **160 plan / 1.600 gün / 2.776 aktivite / 800 geçiş kontrolünde** 0 hata
verdi. Hedefli analiz temiz, odaklı rota regresyonları **80/80**, tam Flutter
paketi **916/916** geçti. Ham stres raporu ve bakım doğrulaması `output/`
altındadır; çalışma henüz commitlenmedi.

### 2026-08-11 — Dış öneri bağlantıları güvenlik bakımı (tamamlandı)

- [x] Mobil hazırlık kartlarındaki tüm eSIM, otel, aktivite, transfer ve tren
      hedeflerini envanterle ve canlı yönlendirmelerle kontrol et.
- [x] Sağlayıcı tarafından verilmemiş `rotori` vanity/affiliate kimliklerini
      kaldır; çalıştığı doğrulanan kanonik sağlayıcı sayfalarına geç.
- [x] Yeni sahte takip kimliği, `/affiliate/` yolu veya HTTPS dışı hedefin
      yeniden eklenmesini engelleyen veri-katmanı regresyonu ekle.

**Sonuç:** Airalo'nun 404 veren `pxf.io/rotori-japan` adresi kaldırıldı; eSIM
önerisi eSIM.io'nun resmî Japonya ürün sayfasına taşındı. İki Klook 404'ü Japonya aktiviteleri ve havalimanı
transferi sayfalarına; Booking'in geçersiz `aid` hedefleri Japonya ülke
sayfasına; doğrulanmamış JR Pass reseller parametresi resmî JR Group sayfasına
taşındı. SmartEX resmî hedefi korundu. Gerçek bir partner programı linki
sağlanana kadar hiçbir kart komisyon/takip iddiası taşımaz.

### 2026-08-11 — Sonradan uçuş ekleme dönüş akışı (tamamlandı)

- [x] Uçuş formundaki alan-bazlı otomatik kaydı ve ayrı “Günleri yeniden
      düzenle” aksiyonunu kaldır; sayfanın en altında tek “Kaydet” aksiyonu
      bırak.
- [x] Kaydet işlemi uçuş verisini ve uçuş saatlerine göre yenilenmiş
      varış/dönüş günlerini tek plan snapshot'ı olarak kalıcılaştırsın.
- [x] Başarı bilgisinden sonra viewer sandviç paneline dön ve “Uçuşlar”
      akordiyonunu açık göster.
- [x] Form, navigasyon sonucu ve drawer açılma durumunu widget regresyonlarıyla
      doğrula; dar mobil ön izlemeyi kontrol et.

**Sonuç:** Uçuş alanları artık kayda kadar yerel taslaktır. Tek “Kaydet”
uçuş bacaklarını senkronlar, yalnız varış/dönüş gününü yeniden kurar ve aradaki
manuel rota düzenlemelerini korur. Bilgi dialog'undan sonra viewer sonucu
doğrudan alır, sandviç panelini açar ve “Uçuşlar” akordiyonunu genişletir.
Yeni 2 widget dosyasındaki **6/6** regresyon, viewer ile birleşik **36/36**
test ve tam Flutter paketi **848/848** başarılı; hedefli analiz temiz. iPhone
dar web ön izlemesinde tek alt aksiyon ve bilgi popup'ı görsel doğrulandı.

### 2026-08-11 — Rota üretim bakım turu (tamamlandı)

- [x] Şehir geçişi modu değiştiğinde günün transfer satırı, süre/ücret özeti,
      moda bağlı başlığı ve rota snapshot'ı aynı atomik komutta yenilensin.
- [x] Timeline örnek kimliği ile kanonik mekan kimliğini ayır; `usj` /
      `os-usj` ve “Universal Studios Japan” / “Universal Studios” alias'larını
      tek mekan sayarak ardışık gün tekrarını hard çıktı invariant'ı yap.
- [x] Mevcut 100×4 optimizer harness'ını yeniden çalıştır; ayrıca gerçek plan
      üretim hattında 100'den fazla şehir/tarih/dil kombinasyonunu inceleyen QA
      matrisi ekle.
- [x] Algoritma sözleşmesi, kalite kapıları, ölçüm özeti ve örnek/failure
      kayıtlarını başka modellerin inceleyebileceği versioned JSON paketine
      çıkar.

**Sonuç:** `DayPlan.cityTransition` tek doğru kaynak oldu; timeline geçiş
satırı `isCityTransition` metadata'sı taşıyor ve mod değişiminde başlık,
süre/ücret, gün teması, kalan saatler ve route snapshot atomik yenileniyor.
`TimelineItem.placeId` ile örnek/katalog kimliği ayrıldı; USJ alias kaçağı
kapatıldı ve ardışık gün kanonik tekrar güvenlik ağı eklendi. Gerçek mobil
üretim QA'sında **160 plan / 1.600 gün / 2.776 aktivite / 800 geçiş-modu
kontrolü**: 0 boş gün, 0 ardışık tekrar, 0 geçiş uyuşmazlığı. Mevcut optimizer
harness'ında **100 base × 4 profil / 4.252 gün**: 0 hard ihlal, 0 tekrar,
0 must-do düşürme, 0 eksik dönüş, 0 infeasible gün; düşürme %1,69. Hedefli
domain testleri **83/83**, viewer testleri **30/30**, tam Flutter paketi
**846/846** başarılı ve değişen rota dosyalarının analizi temiz. İnceleme paketi ile iki ham
rapor `output/rotori-route-*.json` altında.

### 2026-08-10 — Rota deneyimi refactor'u Faz 0–4 tamamlandı

**Kırmızı çizgi:** Beam search, beam width 6, yönlü matris, hard constraint,
must-do/fixed koruması, dört profil ve bağımsız validator ölçüm olmadan
değiştirilmeyecek.

**Şu anki sıra:**

1. ✅ Algoritma davranış sözleşmesini tek regresyon testiyle kilitle.
2. ✅ `RouteLeg` hat/yön/karmaşıklık bilgisini kayıpsız taşısın.
3. ✅ Saf `RouteExecutionLeg` adaptörünü ekle.
4. ✅ Ulaşım ayaklarını ön izleme ve kaydedilmiş günlük timeline'a bağla.
5. ✅ Versioned route snapshot, varsayım özeti, şehir geçişi ve bağlı bilet
   akışını tamamla.
6. ✅ Hedefli test + rota harness + analiz + dar ekran web QA çalıştır.
7. ✅ Yeni planların normal gezi günleri kayıt öncesinde mevcut optimizer ve
   validator hattından geçiriliyor.
8. ✅ Google Routes çalışma zamanı entegrasyonunu kaldırıp şehir,
   semt/istasyon, yön ve zaman bandı duyarlı offline Japonya rota paketini
   varsayılan matris kaynağı yapmak.
9. **Sıradaki:** Offline paket sürelerini gerçek saha örnekleriyle periyodik
   kalibre etmek; canlı gecikme/peron bilgisini navigasyon uygulamasına bırakmak.

Detay: `docs/ROUTE_EXPERIENCE_REFACTOR_PLAN.md`.

---

> Aşağıdaki monetizasyon işi rota deneyimi başlangıç teslimatından sonra devam
> edecek ikinci aktif iş paketidir. Devam ederken önce
> `docs/MONETIZATION_PLAN.md` okunur (özellikle §3 SKU'lar, §4 yayın kapsamı,
> §5 Faz 1, §9 karar günlüğü). **Model kararını yeniden tartışma** — §9.1'de
> kanıtın sınırları ve §9.2'de yeniden değerlendirme kapısı yazılı.

**Durum:** Faz 0 (App Store Connect ürün tanımları) **kullanıcıda**, henüz
yapılmadı. Faz 1 kodu başlamadı.

**Kullanıcı tarafında bekleyen (kod yazmayı bloke ETMEZ, sandbox testini eder):**

1. App Store Connect → abonelik grubu `rotori_pro`
   - `com.mennansevim.rotori.pro.yearly` — TR ₺499 / global $29.99,
     **7 gün ücretsiz deneme** introductory offer
   - `com.mennansevim.rotori.pro.monthly` — TR ₺99 / global $4.99,
     **deneme yok**
2. Small Business Program başvurusu (komisyon %30 → %15)
3. `rotori-social/data/automation_config.json` → `topic.enabled: false`
   açılacak mı? **Kullanıcıya sorulmuş, cevap alınmadı** — bilinçli
   kapatıldıysa dokunulmaz (bkz. `docs/GROWTH_SEO_STRATEGY.md` §6 sıra 1)

**Kod tarafında ilk iş:** aşağıdaki "Sıradaki Uygulama Adımı" listesi.

---

## Aktif Hedef

Monetizasyon modeli pazar araştırmasıyla kararlaştırıldı ve üç belgeye işlendi
(`MONETIZATION_PLAN.md`, `GROWTH_SEO_STRATEGY.md`, `DECISIONS.md` 2026-08-10
ve 08-10b). Model: **yıllık ₺499 + aylık ₺99 abonelik, yıllıkta 7 gün deneme,
kişiselleştirilmiş ön izleme hunisi.** Bu bir hipotez; ilk 100–200 nitelikli
kullanıcı verisinden sonra yeniden değerlendirilecek.

Sıradaki iş **Faz 1**: `in_app_purchase` entegrasyonu, Apple makbuz
doğrulaması yapan Edge Function, `subscriptions` tablosu, Apple S2S V2
bildirim endpoint'i ve `premiumProvider`'ın istemci-prefs'ten sunucu
yetkilendirmesine taşınması. Okuma tarafı (`is_premium()`) zaten var;
**yazan taraf ve süre kontrolü yok.**

Önceki sprint (rota optimizasyonu Faz 0–5) tamamlandı: schema v2, cross-day
assignment, priority-aware dropping, bağımsız hard validator, kişi/grup
maliyeti, transfer timeline, paired profil suite. 100 base × 4 profil kalite
kapısı geçti, analyze temiz.

## Tamamlananlar (bu ve önceki oturumlardan)

- ✅ **2026-08-11** Yeni Rotori uygulama ikonu tüm ürün yüzeylerine uygulandı.
  iOS AppIcon seti paketteki özgün boyutlarla yenilendi; Android launcher ve
  Flutter web/PWA ikonları aynı 1024 px kaynaktan üretildi. Tanıtım sitesinin
  ana, gizlilik, destek, App Store ön izleme ve legacy yüzeyleri ile Rotori
  Social dashboard/stüdyo favicon, ana ekran ve görünür marka işaretleri ortak
  ikon ailesine bağlandı. Dosya boyutu/format, manifest JSON ve görsel yükleme
  kontrolleri tamamlandı.

- ✅ **2026-08-11** Mobil gözlemlenebilirlik temeli eklendi: Sentry crash/hata,
  performance ve güvenli ekran breadcrumb'ları; Supabase'te append-only genel
  ürün olayları ile her rota üretiminin `started/succeeded/failed` fazı,
  sadeleştirilmiş request/result JSON'u ve süre/kalite metrikleri. Çevrimdışı
  outbox, kullanıcı bazlı RLS, hesap silmede cascade ve hassas alanları dışlayan
  JSON sözleşme testleri eklendi. Privacy/App Store metinleri yeni davranışla
  uyumlandı. Flutter **842/842** test başarılı; değişen dosyaların analizi
  temiz ve Sentry Cocoa bağımlılığıyla iOS Simulator debug build tamamlandı.
  Proje genelindeki 17 mevcut uyarı/bilgi bu işten bağımsız kaldı. Canlı kullanım
  için `0009_analytics_observability.sql` migration'ı ile Sentry public DSN
  kurulumu gerekir.

- ✅ **2026-08-11** `feat/premium-iap-foundation`, `social-deploy-tmp` ve
  `social-deploy-fix` geçmişleri `main` üzerinde birleştirildi. Bağımsız eski
  sosyal repo branch'leri güncel `rotori-social/` ağacını geriye götürmeden
  açıklamalı merge commitleriyle bağlandı. Tokyo kataloğunun 12'den 15 yere
  çıkmasıyla eski kalan şehir sayısı regresyonu güncellendi. Doğrulama:
  Flutter **839/839**, rotori-social **171/171** test başarılı.

- ✅ **2026-08-11** Rotori Eats'teki **“Sadece yiyebileceklerimi göster”**
  filtresi katı güvenli moda alındı. Önceki davranış, uygun bir alt türü
  bulunan ana yemeği listede tutuyor ve kart üzerinde “Sorman gerek” veya
  “Uygun değil” hükmü göstermeye devam ediyordu. Anahtar açıkken artık yalnız
  doğrudan `DishVerdict.safe` yemekler listeleniyor; sayaç aynı filtrelenmiş
  kümeyi gösteriyor. Yemek/diyet testleri **45/45**, hedefli analiz temiz;
  iPhone 15 Pro web ön izlemesinde vegan filtre 66 yemekten 5 güvenli yemeğe
  indi ve görünür kartların tamamı “Yiyebilirsin” olarak doğrulandı.

- ✅ **2026-08-10** Gün bazlı etkinlik ekleme akışına **“Biletim /
  rezervasyonum var”** seçeneği eklendi. Biletli etkinlik ile bilet tek atomik
  komutta kimlik üzerinden bağlanıyor; ziyaret tarihi, sabit giriş saati,
  içeride geçirilecek süre ve erken-varış payı kalıcı saklanıyor. Bilet tarihi
  başka plan gününe denk gelirse etkinlik o güne taşınıyor; esnek duraklar hard
  rezervasyonun çevresine yeniden diziliyor. Yer detayından fotoğraf/OCR ile
  eklenen bilet de aynı komut hattını kullanıyor. USJ/Disney için 12 saat + 60
  dakika; teamLab türleri için ürün bazlı süre + 30 dakika varsayılanı var.
  Etkinlik bazlı erken-varış payı rota optimizer'ına aktarılıyor. Alt menüde
  silinen **Keşfet** butonu geri getirildi ve keşif haritasına bağlandı.
  Doğrulama: yeni domain testleri, plan motoru regresyonları ve iki dar mobil
  widget senaryosu geçti; değişen dosya analizi temiz, iPhone 15 Pro web
  önizlemesinde Keşfet görünümü doğrulandı.

- ✅ **2026-08-10** Deneyim rehberi ve Keşfet menüsü son kullanıcı odaklı
  yenilendi. Rehberdeki “Tümü / Tema parkları / teamLab” filtreleri kaldırıldı;
  oyuncak/deneyim stratejileri bir sonraki kartı görünür bırakan yatay kaydırma
  akışına alındı. USJ ve Tokyo Disney için ücretsiz resmî YouTube tanıtım
  bağlantıları eklendi. Her rehber, ziyaret tarihinden satış gününü hesaplayan
  Rotori hatırlatıcısına bağlandı. Hatırlatmalar ekranı artık Shinkansen
  (30 gün), Tokyo Disney ve USJ (60 gün), üç teamLab planlama hedefi için
  çoklu hazır seçim; her seçim için ayrı ziyaret tarihi; bildirim saatinin
  açık anlatımı ve serbest başlık/tarih/saatli özel hatırlatıcı sunuyor.
  Keşfet'te Premium **Fiyat etiketi tara** tam genişlik vitrin kartına çıktı,
  Rotori Eats dört sakin küçük karta taşındı; küçük kartlar düşük doygunluklu
  ortak yüzey diliyle yenilendi. Rota algoritması değiştirilmedi. Doğrulama:
  ilgili domain/widget/viewer testleri **42/42**, hedefli analyze temiz ve
  iPhone 15 Pro web ön izlemesinde etkileşim + yeni hata kaydı kontrolü temiz.

- ✅ **2026-08-11** Hatırlatıcı ürün sınırı Premium olarak netleştirildi:
  mevcut kayıtlar görülüp silinebilir, yeni hazır veya özel hatırlatıcı
  ekleme `premiumProvider` kapısından geçer. Hazır seçimlerde fotoğraf,
  emoji ve marka taklidi kullanılmıyor; altı ürün ayırt edici Material
  ikonları, kontrollü koyu gradyanlar ve ortak seçim diliyle nihai kart
  sunumuna sahip. Tokyo Disney ve USJ resmî site şartları
  ticari yeniden kullanıma izin vermediği, teamLab ticari kullanım için ön
  onay istediği için resmî fotoğraflar uygulamaya kopyalanmadı; resmî
  sayfalar bilgi/doğrulama bağlantısı olarak korunuyor. Rota algoritmasına
  dokunulmadı. Hatırlatıcı, deneyim rehberi, rezervasyon penceresi ve rota
  regresyonlarını kapsayan testler **46/46** geçti; hedefli analiz temiz ve
  iPhone 15 Pro web ön izlemesinde ücretsiz/Premium akışları ile taşma ve
  yeni hata kaydı kontrolü temiz.

- ✅ **2026-08-10** İlk kez gidecek kullanıcılar için iki dilli
  **“Bilet Hazır, Macera Başlasın!”** deneyim rehberi eklendi. Viewer keşfet
  menüsünden açılan enerjik sayfa; USJ, Tokyo Disneyland, Tokyo DisneySea,
  teamLab Planets, Borderless ve Botanical Garden Osaka için bilet alma
  adımlarını, giriş tamponunu, önerilen süreyi, saat saat akışı, içerideki
  öne çıkan deneyimleri ve kritik ipuçlarını tek yerde topluyor. Telifli
  park karakteri/logo içermeyen özgün hero görseli uygulama asset'i olarak
  üretildi; lisansı belirsiz üçüncü taraf tanıtım videosu gömülmeyip USJ'nin
  resmî video kanalına güvenli dış bağlantı verildi. Yeni domain/widget
  testleri **5/5**, viewer regresyonları **34/34** geçti; hedefli analiz temiz
  ve iPhone 15 Pro web ön izlemesinde görsel QA tamamlandı.

- ✅ **2026-08-10** Şehir geçişinden açılan bilet editörünün ESC ile
  kapatılmasında oluşan Flutter lifecycle assertion'ı giderildi. Editörün
  `TextEditingController` nesneleri dialog widget'ının gerçek yaşam döngüsüne
  taşındı; bilet dialog'u geçiş sheet'inin üzerinde açılıyor ve ESC yalnız üst
  dialog'u kapatıyor. Yeni ESC regresyonu dahil viewer testleri **26/26**,
  değişen dosya analizi temiz; web ön izlemesinde gerçek ESC ile doğrulandı.

- ✅ **2026-08-10** Rota deneyimi refactor Faz 2–4 ve Faz 5'in diyet güvenliği
  tamamlandı. Ön izleme ile kaydedilmiş plan timeline'ı artık çıkış/varış,
  ulaşım modu, süre, yürüyüş, gerçek transit beklemesi, aktarma ve grup
  ücretini gösteriyor. Tahmini sonuç hat/yön uydurmadan açık rozetle; güvenilir
  sonuç sağlayıcı hat/yön bilgisiyle gösteriliyor. `RouteExecutionSnapshot`
  schema v1 plan/gün/sürüm/aktivite hash'i/matris sürümü/profil/sağlayıcı
  kimliğiyle saklanıyor ve plan değişince geçersizleşiyor. Şehir geçişi modu
  ile bağlı bilet tek engine hattında düzenleniyor; bilet boş durumu CTA aldı.
  Oluşturma öncesi rota/tarih/uçuş/otel varsayımları görünür ve düzenlenebilir;
  eski JSON geriye uyumlu. Çelişen diyet seçimleri domain seviyesinde
  çözülüyor. Doğrulama: ilgili paket **94/94**, rota harness **15/15**,
  değişen dosya analizi temiz. Proje genel analyze yalnız refactor dışındaki
  mevcut **17** uyarı/bilgiyi raporluyor. Dar ekran web QA tamamlandı.

- ✅ **2026-08-10** Rota deneyimi refactor Faz 0/1 temeli tamamlandı.
  Algoritmanın beam 6, determinizm, sabit rezervasyon, gün sonu dönüşü ve
  bağımsız validator sözleşmesi `route_algorithm_contract_test.dart` ile
  kilitlendi. `RouteLeg`, matristen gelen `lineId`, `directionId` ve
  `complexityPenalty` bilgisini artık kaybetmiyor. Saf Dart
  `RouteExecutionBuilder`, optimizer bacaklarını başlangıç / duraklar arası /
  otele dönüş türleriyle ve reliable/estimated veri kalitesiyle sunum modeline
  çeviriyor; sonuç `PlanOptimizationPreview.executionLegs` üzerinden UI'a
  hazır. Hedefli rota testleri + harness **27/27**, daha geniş ilk rota paketi
  **29/29** başarılı; değişen 6 dosyanın analizi temiz. Proje genel analyze'da
  refactor dışı mevcut 18 uyarı/bilgi devam ediyor.

- ✅ **2026-08-10** Monetizasyon modeli pazar araştırmasıyla kararlaştırıldı ve
  belgelendi. Kod envanteri çıkarıldı: uygulama **hiç yayınlanmamış**
  (`version: 1.0.0+1`, release checklist'te işaretli kutu yok), ödeme
  altyapısı **sıfır** (`in_app_purchase` yok), sunucu yetkilendirmesinin
  **okuma tarafı var yazan yok** (`is_premium()`), rota optimizasyonu
  paywall'ı **satış değil coming-soon duvarı** ve kilidi istemcide
  (bypass edilebilir), l10n **%100 iki dilli** (1240/1240), sosyal hat
  kurulu ama otomasyon 2 gönderi yapmış. Araştırma: RevenueCat 2026
  (seyahat aboneliklerinin %66'sı yıllık, deneme→ödeme %43,5, indirme→ödeme
  medyanı %2, $1K MRR'a 238 gün, yeni seyahat uygulamalarının %9,8'i 2 yılda
  $10K MRR) + rakip modelleri (TripIt $49/yıl, Wanderlog $29.99–49.99/yıl +
  affiliate, Tripsy $59.99/yıl & lifetime $299 = yıllığın 5 katı çıpa,
  NAVITIME ~¥330/ay) + Wanderlog'un 5M indirmeye SEO ile çıkması.
  Karar: **yıllık ₺499 + aylık ₺99 abonelik, yıllıkta 7 gün deneme,
  kişiselleştirilmiş ön izleme hunisi** — "kanıtlanmış model" değil,
  **test edilecek en güçlü hipotez** (RevenueCat verisi yalnızca abonelik
  kullanan uygulamalardan geliyor → seçim yanlılığı; trip-pass hipotez
  olarak açık). Yayın kapsamı 26 → 12.5–15 güne indirildi; offline harita
  paketi, planlama fazı araçları, bilet kasası ve paylaşım yayın sonrasına
  ertelendi. Yeni belgeler: `docs/MONETIZATION_PLAN.md`,
  `docs/GROWTH_SEO_STRATEGY.md`. Commit: `8788454`, `396b6a0`.

- ✅ **2026-08-07** Yeni mobil **price-tag scanner** özelliği ayrı feature
  paketi olarak eklendi (`rotori-mobile/lib/features/price_tag_scanner/`):
  `view/` (tam ekran kamera + merkez viewfinder overlay), `controller/`
  (Riverpod state makinesi: Scanning → ExtractedData → FetchingMockPrices
  → ResultReady → Error, 450 ms frame throttling, single-flight OCR),
  `services/` (1 sn gecikmeli Hepsiburada/Trendyol/Amazon TR mock JSON fiyat
  repository) ve `utils/` (`TagParser`: JPY/model regex parse, ポイント
  eleme, 税込 önceliği). Test: `tag_parser_test.dart` (3 mock OCR bloğu)
  geçti; hedef kapsam analyzer temiz.

- ✅ **2026-08-07** Canlı fiyat çeviriciye ürün pazar sorgu akışı eklendi:
  kamerada sorgulanabilir ürün çerçevesi + `Fiyatı Sorgula` CTA, açılır
  sorgu sheet'inde Hepsiburada/Trendyol/Amazon kaynak ilerlemesi,
  kaynak bazlı fiyat/başarısızlık durumları, karşılaştırma özetinde
  TR medyan/min/max + JP referansı + fark (TL/%). Yeni `scanner.market.*`
  i18n anahtarları eklendi, resolver/controller/widget testleri yazıldı
  (`product_query_candidate_resolver_test`,
  `live_currency_scanner_controller_test`,
  `live_currency_scanner_page_query_ui_test`). Doğrulama:
  scanner hedef kapsamında `flutter analyze` temiz; ilgili test setleri yeşil.

- ✅ **2026-08-07** Viewer P0 test kırıkları güncel UI davranışına hizalanarak
  kapatıldı. `checklist_screen_test.dart`, `budget_screen_test.dart` ve
  `plan_viewer_test.dart` senaryoları yeni drawer/edit/bütçe yüzeyine göre
  stabilize edildi (eski `⋮` menü ve sabit toplam metni beklentileri
  kaldırıldı; drag/sheet/undo akışı doğrulandı). Doğrulama: hedefli viewer
  test paketi yeşil, ardından tam paket `flutter test` **+566 passed** ve
  `flutter analyze` temiz.

- ✅ **2026-08-06** rotori-social deploy hattı tek monorepo akışına alındı:
  Pi5'te bağımsız `~/rotori-social` git klonu arşivlenip çalışma dizini
  `~/rotori-app/rotori-social` oldu; servis bu dizinden rebuild edildi ve
  `commit=cbff51e` ile ayağa kalktı. Geriye uyumluluk için
  `~/rotori-social -> ~/rotori-app/rotori-social` symlink'i bırakıldı.
  Yerelde `social` remote kaldırılarak tek remote (`origin`) düzenine geçildi.

- ✅ **2026-08-06** rotori-social otomasyon zamanlama düzeltmesi:
  (1) `next_automation_slot` lane-aware hale getirildi; `news` ve `topic`
  otomasyonları artık slot hesaplamasında birbirini yanlışlıkla bloke etmiyor
  (legacy/manual kuyruk girdileri korumalı bloklayıcı kalıyor). Böylece
  "bugün +5 dk" gibi yakın zaman hedefleri başka lane çakışması yüzünden
  haftalara ötelenmiyor. (2) `news_automation` CLI `--publish` argümanını
  destekleyecek şekilde güncellendi; launchd auto_publish çağrısı artık
  geçerli akışa düşüyor (`run_once_with_publish`). (3) Regresyon testleri:
  `test_contracts_scheduler.py` yeni near-future lane izolasyonu + same-lane
  bloklama senaryoları ve `test_news_automation_cli.py` ile `--publish`
  kontratı eklendi. Hedef test setleri yeşil (9 + 58 test).

- ✅ **2026-08-06** Viewer kalite turu (kritik geri bildirim düzeltmeleri):
  (1) Akıllı rota sheet'inde "Güvenilir rota verisine ulaşılamıyor" diye
  maskelenen hatanın kök nedeni ayrıştırıldı; matrix fallback zaten varken
  optimizer infeasible kaldığında hard-error veriyordu. `PlanOptimizationController`
  artık `noFeasibleRoute/routeDataMissing/fixedConflict/protectedInfeasible`
  durumlarında **yerel kural tabanlı fallback preview** üretir (aktiviteleri
  korur, karşılaştırma kartı açılır, kullanıcı uygulayabilir). Ayrıca hata
  metinleri failure code'a göre ayrıştırıldı (`noFeasible`, `fixedConflict`,
  `routeDataMissing`, `dataIssue`) — simülasyon kaynaklı yanlış alarm azalır.
  (2) Drawer'daki "Yemek rehberi" aksiyonu artık must-know yerine yeni
  `FoodGuideScreen` açıyor; bu ekranda canlı birim maliyet tablosundan kısa
  fiyat referansları + aktif diyet tercihleri + pratik yemek ipuçları var.
  (3) "Mutlaka Bilmeniz Gerekenler" üst başlık çipleri, istek doğrultusunda
  dropdown filtreye çevrildi; "Tümü" veya seçili konuya göre alt içerik
  gösterilip gizleniyor. Hedef analiz temiz, controller testleri (9/9) yeşil.

- ✅ **2026-08-06** Route regression follow-up: `PlanViewerScreen` view modunun
  varsayılanı tekrar **aktif gün açık** olacak şekilde sabitlendi (rota
  aksiyonlarının görünürlüğü korunuyor). `plan_viewer_test` içindeki
  karşılaştırma/onay senaryosu, scrollable bottom sheet'te onay butonuna
  dokunmadan önce `ensureVisible` kullanacak şekilde stabilize edildi.
  Hedefli rota testleri yeniden yeşil.

- ✅ **2026-08-06** Keşif haritası rütbe-kazanım kutlaması okunabilirlik
  iyileştirmesi: eski tam ekran yarı-transparan metin katmanı yerine yüksek
  kontrastlı merkez kart + bulanık/karartılmış backdrop modeline geçirildi
  (örnek uygulamalardaki achievement modal desenine benzer). Yazı hiyerarşisi
  sadeleştirildi (label → romaji → açıklama → CTA), otomatik kapanış süresi
  hafif uzatıldı ve kutlama açıkken keşif/snackbar bildirimleri bastırılarak
  çakışma kaldırıldı.

- ✅ **2026-08-06** Mobil viewer yardımcılarında beş iyileştirme: (1) Rehber
  ("Mutlaka Bilmeniz Gerekenler") ekranına en üstte gruplanmış "Konu
  Başlıkları" hızlı erişim rozetleri eklendi (dokununca ilgili bölüme kaydırır)
  ve yeni "Acil Durum ve Güvenlik" bölümü (110/119, JNTO yardım hattı,
  sigorta, Safety tips app, büyükelçilik) yazıldı. (2) Canlı fiyat çevirici
  artık AR "yerinde" mod: çevrilen tutar algılanan fiyat kutusunun tam üzerine,
  opak zeminle yerleştiriliyor — kamera görüntüsünde fiyat sanki TL yazıyormuş
  gibi görünüyor. (3) Taraycıdan geri dönüş hatası düzeltildi: drawer artık
  `context.push` kullanıyor, geri tuşu plan listesine değil viewer'a döner.
  (4) Sandviç panel KEŞFET karoları yalnız-ikon yapıldı (etiketler kaldırıldı,
  erişilebilirlik için Tooltip/Semantics'e taşındı); sert beyaz zemin yumuşak
  accent tonuyla dengelendi. (5) Bütçe ekranına yıl bazlı, AI KULLANMAYAN
  tahmini gider dökümü eklendi: düzenlenebilir `assets/data/unit_costs.ini`
  birim maliyet tablosu (yetişkin/çocuk, mevsim çarpanı) + saf-Dart
  `cost_estimate.dart` tahmincisi (uçak/otel/yemek/tren/taksi/alışveriş/
  elektronik/gezi min–max) + "Bu rota sizin için ₺X – ₺Y" başlığı, kalem kalem
  satırlar ve örnek birim fiyatlar (ramen, shinkansen vb.). `flutter analyze`
  temiz; yeni `cost_estimate_test.dart` dahil 25 test yeşil.


- ✅ **2026-08-05** rotori-social otomasyon görünürlüğü iyileştirildi: yayın
  kuyruğu girdilerine son deneme zamanı/sonuç zamanı/deneme sayısı ve
  başarısızlık nedeni metadata alanları eklendi; dashboard aggregation
  (`/api/dashboard/publishes`, `overview`, `timeline`) artık
  `publish_outcome`, `publish_outcome_tr`, `failure_reason`, `is_overdue`
  alanlarını döndürüyor. Automation ekranına altta "Yayın Logu (Son
  Durumlar)" kartı eklendi; burada **başarılı/başarısız durum**, **yayın
  tarihi** ve **neden yayınlanmadı** bilgisi satır bazında görünüyor. Aşırı
  cache nedeniyle eski JS'in kalmaması için dashboard script cache-bust sürümü
  güncellendi.

- ✅ **2026-08-05** Viewer/yardımcı özelliklerde hızlı kalite turu:
  (1) Planlar ekranında çıkış için onay diyaloğu eklendi (yanlışlıkla logout
  riski azaltıldı), (2) Japonca TTS asset oynatma hızı cümle uzunluğuna göre
  normalize edildi (çok hızlı örnekler yavaşlatıldı), (3) Bütçe ekranına
  aile odaklı "güvenli üst limit" tahmini (JPY + TRY, aktarma/tek-yön
  varsayımlı) eklendi, (4) Must-know içine ATM/debit vs kredi kartı nakit
  avans limiti uyarısı güçlendirildi, (5) yer detay sheet'ine yakındaki
  restoranları haritada açan hızlı liste eklendi ve bilet-kaynağı modalinde
  daha güvenli Material/Ink etkileşimi kullanıldı, (6) canlı para tarayıcıda
  kamera/stream/OCR hata yolları için durum anahtarlı hata mesajları ve
  detaylı debug logları eklendi. `flutter analyze` temiz; scanner widget
  testleri yeşil. (Mevcut welcome-flow test kırıkları bu işten bağımsız olarak
  sürüyor.)

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

- ✅ **2026-08-03** eski sosyal proje dizininin kaynak kodu
  doğrudan `rotori-social/` altına taşındı ve nested `.git`
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

- [ ] **Viewer sheet kapanma ergonomisi (Apple uyumlu)**
  - Alt açılır detay sayfasında kapanma etkileşimi zor hissediliyor.
  - İyileştirme: drag-to-dismiss hassasiyet ayarı, üstte görünür `Kapat (X)` aksiyonu,
    dış alana dokunarak kapatma (modal kısıtları uygunsa) ve scroll/drag çakışmasını azaltma.
  - Kabul kriteri: tek elle kullanımda ilk denemede kapanma oranı artmalı,
    uzun içerikte sheet "takılıyor" hissi belirgin şekilde azalmalı.

- [ ] **Timeline saat kolonu boşluk optimizasyonu**
  - Soldaki saat ve timeline ray etrafındaki yatay boşluk fazla; içerik alanı daralıyor.
  - İyileştirme: saat kolonu genişliğini ve saat-sol/sağ padding'i küçült,
    kart içeriğine daha fazla alan aç.
  - Kabul kriteri: küçük ekranlarda (özellikle iPhone dar genişlik) satır taşması azalmalı,
    görsel denge korunmalı.

- [ ] **GPS akıllı takip (pil dostu, kullanıcıyı yormayan model)**
  - Hedef: Kullanıcının bazı bölgelerde ~10 dakika kaldığını tespit etmek,
    sürekli açık GPS zorlamadan ve her seferinde manuel açtırmadan.
  - Önerilen yaklaşım (Apple doğasına uygun): Visit + Significant Location +
    dinamik geofence + kısa süreli yüksek doğruluk burst doğrulaması.
  - Ürün yüzeyi: tek ana anahtar (`Akıllı Konum Takibi`), gezi tarih aralığında
    otomatik aktif/pasif, pil modu seçenekleri (Tasarruf/Dengeli/Hassas).
  - Kabul kriteri: 10 dk kalış tespiti false positive üretmeden çalışmalı,
    pil tüketimi "always-on GPS" seviyesine çıkmamalı.

- [ ] Offline Japonya rota paketini gerçek saha örnekleriyle periyodik kalibre
  et; paket sürümünü uygulama güncellemeleriyle yenile.
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

- Native `integration_test` koşusu için bağlı iOS/Android cihaz veya emulator
  yok. Web integration runner desteklenmiyor; macOS desktop hedefi projede
  yapılandırılmamış. Aynı kritik sözleşmeler normal Flutter test paketinde
  çalışıyor.
- Sunucuda plan revision/CAS alanı yok; aynı plan iki cihazda aynı anda
  değiştirilirse cihaz içi sıra ve dirty-cache korumasına rağmen son yazan
  kazanabilir.

## Sıradaki Uygulama Adımı — Faz 1 iş emri (v2, düzeltilmiş)

> **Mimari sözleşme: `docs/ARCHITECTURE.md` §8b.** Ürün/fiyat kararı:
> `MONETIZATION_PLAN.md`. Bu liste sıralı yürütülür; §8b'den sapma olursa
> önce §8b güncellenir (proje kuralı: koddan önce doküman).
>
> **Bu listenin v1'i iki ciddi hata içeriyordu** (dış inceleme yakaladı,
> 2026-08-10): (a) `original_transaction_id` unique + `transactionId`
> idempotency'si tutarsızdı — ikisi farklı kimlik, ilki abonelik ömrü boyunca
> sabit, ikincisi her yenilemede değişir; tek tabloda birleştirmek
> yenilemeleri kırar. (b) Yetki kaynağı olarak `raw_user_meta_data`
> öneriliyordu — **bu alan kullanıcı tarafından yazılabilir**, yetkilendirmede
> kullanılamaz. İkisi de aşağıda düzeltildi.

### 1. Üç tablolu şema — `supabase/migrations/0009_subscriptions.sql`

- [ ] `subscription_entitlements` — güncel durum,
      `original_transaction_id` **UNIQUE**; alanlar §8b.2'de
- [ ] `app_store_transactions` — değişmez geçmiş, `transaction_id` **UNIQUE**
      (gerçek replay koruması burada; her yenileme yeni satır)
- [ ] `app_store_notifications` — `notification_uuid` **UNIQUE**
      (bildirim idempotency'si)
- [ ] RLS: self-read; INSERT/UPDATE yalnız service_role
      (`0008_daily_scans.sql` deseni)
- [ ] Tüm `SECURITY DEFINER` fonksiyonlarda `set search_path = public`,
      açık `REVOKE`/`GRANT`
- [ ] `subscription_entitlements.user_id` için cascade delete **dikkatli** —
      §8b.9 (yasal saklama vs hesap silme)

### 2. `is_premium()` tabloya bağlanır — **mevcut güvenlik açığını kapatır**

- [ ] `is_premium()` yeniden yazılır: **yalnız `subscription_entitlements`**
      okur (§8b.3 sorgusu). `raw_user_meta_data` yetkilendirmede **hiç
      kullanılmaz** — kullanıcı o alanı `auth.updateUser` ile kendisi
      yazabiliyor, yani şu an tarama kotası (10/100) aşılabilir durumda
- [ ] `expires_at` **veya** `grace_period_expires_at` geçerliyse aktif;
      `refunded`/`revoked` her durumda kapalı
- [ ] **`parse-price-tag/index.ts:178` bu fonksiyonu çağırıyor** —
      imza korunur, tarama kotası regresyona girmez

**Kabul:** Süresi geçmiş abone `false`; grace period içindeki abone `true`;
iade edilmiş abone `false`; metadata'sını elle `premium: true` yapan kullanıcı
`false`; tarama kotası testleri yeşil.

### 3. JWS doğrulama + hesap sahipliği — `supabase/functions/verify-purchase/`

- [ ] App Store Server API ile `signedTransactionInfo` **JWS imza**
      doğrulaması (legacy `/verifyReceipt` kullanılmaz)
- [ ] `bundleId` (`com.mennansevim.rotori`) + `productId` + `environment`
      + `expiresDate` doğrulanır
- [ ] **`appAccountToken` sahiplik kontrolü** (§8b.4): JWS içindeki değer
      oturumdaki Supabase `user_id` ile eşleşmezse yetki **açılmaz**
- [ ] `app_store_transactions`'a `transaction_id` ile idempotent insert;
      `subscription_entitlements`'a `original_transaction_id` ile upsert
- [ ] Yetki **yalnız tabloya** yazılır; metadata'ya yazılmaz (§8b.1)

### 4. S2S V2 endpoint + reconciliation — `supabase/functions/apple-notifications/`

- [ ] `signedPayload` imza doğrulaması
- [ ] `notification_uuid` ile idempotent kayıt (tekrar gelen bildirim iki kez
      işlenmez)
- [ ] Olaylar: `SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW`,
      `GRACE_PERIOD_EXPIRED`, `EXPIRED`, `DID_CHANGE_RENEWAL_STATUS`,
      `DID_CHANGE_RENEWAL_PREF`, `REFUND`, `REVOKE` — **durum makinesi
      §8b.5'e göre**, olay adına göre düz `switch` değil
- [ ] **Eski bildirim yeni durumu ezmez** (sıra dışı teslim korumalı)
- [ ] Şüpheli/eksik durumda `Get All Subscription Statuses` ile uzlaştırma
- [ ] Production ve sandbox endpoint'leri **ayrı**; Notification History
      kurtarma yolu tanımlı
- [ ] `grace_period_expires_at` Apple'ın verdiği değerden yazılır — elle
      "tolerans" hesaplanmaz

**Neden atlanamaz:** Bu olmadan iptal/iade sonrası erişim süresiz açık kalır.

### 5. İstemci — `rotori-mobile/lib/features/premium/purchase_service.dart`

- [ ] `in_app_purchase: ^3.3.0` + **`in_app_purchase_storekit: ^0.4.11`**
      (JWS `serverVerificationData` 0.4.2'de, deneme uygunluğu 0.4.3'te geldi;
      3.3.0 iOS'ta StoreKit 2'yi varsayılan kullanıyor). **v1'deki `^3.2.0`
      JWS planıyla uyumsuzdu**
- [ ] `purchaseStream` dinleyicisi **uygulama açılışında en erken** kurulur
- [ ] Satın alırken Supabase UUID `appAccountToken` olarak verilir (§8b.4)
- [ ] Sunucu doğrulaması → yetki → **`completePurchase()`** (3 gün içinde
      tamamlanmayan işlem iadeye yol açabilir)
- [ ] **Kalıcı "bekleyen doğrulamalar" kuyruğu** — doğrulama sırasında ağ
      koparsa işlem kaybolmaz, bağlantı gelince tekrar denenir
- [ ] `restorePurchases()`
- [ ] Hata durumları: mağaza erişilemez, ürün yok, ödeme reddedildi,
      pending (Ask to Buy / SCA), ağ yok
- [ ] **Deneme uygunluğu StoreKit 2 intro eligibility API'sinden** okunur —
      yerel `trial_used` anahtarı **kullanılmaz** (reinstall/çoklu cihazda bozulur)

### 6. `premiumProvider` — cache yalnız UI (§8b.6)

- [ ] Tek doğru kaynak sunucu; cache **yalnız arayüz kolaylığı**
- [ ] Ücretli sunucu işlemleri (AI rota keşfi, tarama kotası) her zaman
      backend'de korunur — cache'e güvenilmez, kırılması gelir sızıntısı değil
- [ ] Cache'e son güvenilir **sunucu zamanı** yazılır (cihaz saati geri
      alınabilir)
- [ ] `kPremiumPrefsKey` → `'premium_entitlement_cache'`; debug override ayrı
      anahtara (`'debug_premium_override'`), yalnız `kDebugMode`
- [ ] `price_tag_scanner/controller/scanner_controller.dart:268` aynı anahtarı
      okuyor — birlikte güncellenir

### 7. Testler

- [ ] `premium_gates_test.dart` yeniden yazılır — satır 67–71 eski prefs
      sözleşmesini kilitliyor, **kasıtlı kırılacak**. Eats ücretsizliği
      testleri (80–99) **aynen korunur**
- [ ] Sunucu tarafı senaryo matrisi: yanlış JWS imzası · yanlış
      bundle/product/environment · başka kullanıcıya ait `appAccountToken` ·
      aynı `transaction_id` tekrarı · aynı `notification_uuid` tekrarı · eski
      bildirimin yeni yenilemeyi ezmemesi · grace period başı/sonu ·
      aylık↔yıllık geçiş · refund/revoke · hesap silinmişken S2S bildirimi ·
      ağ kesikken satın alma + yeniden doğrulama · restore + yeniden kurulum ·
      tarama kotası regresyonu
- [ ] **"Release build'de debug override okunmuyor" unit testle
      kanıtlanamaz** — Flutter unit testleri debug modda koşar, `kDebugMode`
      true. Bunun için **release-mode cihaz smoke testi** gerekir

### 8. Hukuki metinler ve destek sayfası — App Store blokeri

- [ ] **Kullanım Şartları sayfası YOK** — `rotori-website/`'da yalnız
      `privacy-tr/en`, `destek-tr`, `support-en` var. Abonelik için
      oluşturulmalı (TR + EN)
- [ ] `rotori-website/destek-tr.html:63` hâlâ *"Rotori şu an tamamen
      ücretsizdir. Reklam yok, abonelik yok, uygulama içi satın alma yok"*
      diyor → güncellenir (`support-en.html` de)
- [ ] Privacy Policy'ye eklenir: satın alma işlem kimlikleri, abonelik
      statüsü, saklama süresi, Apple ↔ Supabase veri akışı
- [ ] Hesap silme ekranına §8b.9 uyarısı + "Aboneliği yönet" bağlantısı

### 9. App Store Connect yapılandırması (kullanıcı)

- [ ] Production **ve** sandbox S2S bildirim URL'leri
- [ ] App Store Server API: anahtar, issuer ID, key ID + rotasyon görevi
- [ ] Subscription group içinde aylık/yıllık **seviye sırası** ve
      upgrade/downgrade davranışı tanımlanır

### Faz 1 sonrası (aynı branch'te devam)

6. **Faz 2** — paywall ekranı (iki SKU, yıllık varsayılan + "en avantajlı",
   deneme yalnız yıllıkta), Apple abonelik açıklama maddeleri, restore butonu,
   ToS/Privacy linkleri, `l10n.dart:2646` "sunulacak" kopyasının değişmesi,
   **rota optimizasyonu AI çağrısının Edge Function'a taşınması** (şu an kilit
   `plan_viewer_screen.dart:4055`'te istemcide, prefs ile aşılabilir)
7. **Faz 3** — ön izleme hunisi (ilk oturumda tamamlanmalı: denemelerin %82'si
   kurulum günü başlıyor), "kazandırdığı saat" göstergesi
   (`plan_optimization_controller.dart:44` `totalTravelMinutes` farkı —
   **fallback yolundan gelen sonuçta gösterilmez**), gezi limiti 1 aktif
8. **Faz 4** — `rotori-mobile/docs/IOS_RELEASE_MANUAL_GATE_CHECKLIST.md`
   baştan sona (şu an tek kutu işaretli değil — **gerçek kritik yol bu**)

## Şu An Değişen Dosyalar

Çalışma dizini aktiftir ve birden fazla iş paketi commit'lenmeden birlikte
durmaktadır: rota/biletli aktivite geliştirmeleri, deneyim rehberi +
hatırlatıcılar + Keşfet tasarımı ve `rotori-social/` otomasyon değişiklikleri.
`.claude/launch.json` ile `rotori-social/data/*` çalışma-zamanı/yerel durum
dosyaları kullanıcıya aittir; mobil özellik işi bu dosyaları değiştirmez veya
geri almaz. Checkpoint alınırken kapsam dosya bazında açıkça ayrılmalıdır.

## 2026-08-11 — Premium Japonca çevrimdışı metin çevirisi

- [x] Japonca sekmesine TR/EN ↔ JA cihaz-üstü metin çeviri kartı eklendi.
- [x] İlk kullanımda iki ML Kit dil paketini indiren, sonrasında çevrimdışı
      çalışan model yönetimi eklendi.
- [x] Mikrofonlu konuşma modu, konuşma izinleri ve runtime ses bağımlılıkları
      App Store sürümünden kaldırıldı; aşağıdaki hazır ifade sesleri yerel MP3
      asset'leriyle çalışmaya devam ediyor.
- [x] Çevirmen `premiumProvider` kaynağına bağlandı. Ücretsiz kullanıcıda en
      üstte kilitli premium kartı görünür; premium açılınca metin alanı ve model
      indirme akışı otomatik açılır.
- [x] Google Translate sonuç atfı ve otomatik çeviri doğruluk uyarısı eklendi.
- [x] TR/EN gizlilik politikası yalnız cihaz-üstü metin çevirisini anlatacak
      şekilde güncellendi; App Store inceleme notu ve QA matrisi sadeleştirildi.
- [x] Web conditional stub ile derleme korunuyor; mobil-only aksiyonlar ön
      izlemede açıklamalı olarak pasif.
- [x] Eksik `/price-tag-scanner` ve `/live-currency-scanner` preview rotaları
      eklendi; fiyat etiketi tarama sayfası görsel QA'da açıldı.
- [x] Premium kilitte model kontrolünün başlamadığı ve premium metin çevirisinin
      çalıştığı widget testleri eklendi.
- [ ] Gerçek iPhone'da dil paketlerini indirip uçak modunda iki yönlü metin
      çevirisi tamamlanacak. 11 Ağustos denemesinde debug build ve Apple
      imzalama tamamlandı; iOS 27 cihazına yükleme Xcode 26.6'nın developer disk
      image'ı bağlayamaması nedeniyle durdu. Uyumlu Xcode/device support ile
      yeniden denenmeli.
- [ ] Android debug APK kontrolü CameraX/Gradle hattındaki mevcut
      `CallbackToFutureAdapter` compile-classpath hatasında durdu; ses katmanı
      öncesindeki bu bağımlılık uyumsuzluğu ayrı Android build işi olarak
      çözülmeli.

## 2026-08-11 — Günlük geçişleri kompaktlaştırma

- [x] Günlük akıştaki büyük yürüyüş/ulaşım kartları ikon, duraklar, tür ve
      süreyi taşıyan tek satırlık kompakt satırlara çevrildi.
- [x] Kullanıcı optimizasyon çalıştırmadan önce de başlangıç, duraklar arası ve
      güne dönüş geçişleri mevcut sıra üzerinde kompakt olarak gösteriliyor;
      veri kalitesi görünür bir `TAHMİNİ` etiketi yerine iç modelde korunuyor.
- [x] Onaylanmış rota snapshot'ı varsa tahmini satırlar yerine kaydedilmiş
      gerçek/tahmini ayaklar aynı kompakt sunumla kullanılıyor.
- [x] İlk plan üretiminin yerel kural/katalog tabanlı, tam rota
      optimizasyonunun ise ayrı beam-search + validator hattı olduğu ürün
      sözleşmesinde açıkça ayrıldı.
- [x] Hedefli analiz temiz; proje genelindeki **826 Flutter testi** geçti.

## 2026-08-11 — İlk rota üretimini gerçek optimizasyona bağlama

- [x] Kompakt geçişlerde `TAHMİNİ` metnini ve pembe kart zeminini kaldır;
      veri kalitesini model/semantics katmanında koru.
- [x] Havaalanı→otel ve otel→havaalanı satırlarının genel açıklamasını kaldır;
      hesaplanan varış saati, süre ve havalimanına uygun tren/metro/otobüs/
      taksi seçenekleriyle değiştir.
- [x] Timeline aktivitesine çalışma saati penceresini geriye uyumlu taşı ve
      optimizer adapter'ında hard opening/closing constraint olarak kullan.
- [x] Sağlayıcıdan bağımsız gateway sınırı korunarak ilk entegrasyon hazırlandı;
      sonraki offline kararı bu Google çalışma zamanı ayrıntısını supersede etti.
- [x] Yeni planın normal günlerini kayıt öncesinde yönlü matris,
      beam-search ve bağımsız validator ile optimize edip route snapshot'ını
      başlangıçtan üret.
- [x] Matris üretilemezse planı kaybetmeden offline paket fallback'i kullan;
      uçuş/otel/şehir transferi gibi sabit özel günlerin sırasını değiştirme.
- [x] Domain/controller/widget testleri, analyze ve iPhone dar ekran QA.

## 2026-08-11 — Ücretsiz ve tamamen offline rota matrisi

- [x] Google Routes'a özel mobil gateway ve Edge Function'ı kaldır.
- [x] Tokyo, Kyoto, Osaka ve Hiroshima için semt/istasyon kümeleri, özel zor
      bağlantılar ve şehir ulaşım profilleri ekle.
- [x] Diğer desteklenen şehirler için kalibre genel profil; bilinmeyen noktalar
      için muhafazakâr fallback ekle.
- [x] Yürüyüş, toplu taşıma ve araç-başı taksi alternatiflerini ilk/son yürüme,
      bekleme, aktarma ve istasyon tamponlarıyla üret.
- [x] Matris sürümüne paket, gün türü ve zaman bandını kat; kesin hat/yön
      uydurma, bütün sonuçları tahmini olarak işaretle.
- [x] Üretim ve preview girişlerini aynı offline repository'ye bağla.
- [x] Kısmen dolu günleri şehir genelinden rastgele aktiviteyle şişirme;
      yalnız öğün molası ekle. Disney/USJ/teamLab gibi tam/yarım gün çapalarını
      dolgu havuzundan çıkar; çift dilli katalog tekrarlarını kimlikle ele.
- [x] Domain/data/controller/widget regresyonları, tam test ve analiz:
      offline matris aşamasında **836/836** Flutter testi, nihai yerellik
      düzeltmesinden sonra etkilenen **91/91** üretim/rota/viewer testi geçti.
      Değişen dosyaların analizi temiz; proje genelinde yalnız önceden var olan
      rota dışı 17 uyarı/bilgi kaldı.

## Son Commit'ler (referans)

```
4578280 feat(website): baştan aşağı revizyon — Design System v2
70c82d2 fix(test): plan_viewer + day_map regresyonlarını çöz — F2.0
cbd592a copy(website): 'Hesap gerekmez' → 'Ücretsiz · reklamsız'
08d7449 feat(website): Privacy Policy + Destek sayfaları + footer link
11f3541 feat(release+web): F1 App Store prep — Info.plist, hesap silme
```
