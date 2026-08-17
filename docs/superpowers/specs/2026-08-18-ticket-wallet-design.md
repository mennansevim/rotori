# Rotori Wallet — Bilet Ekleme ve Listeleme Tasarımı

**Tarih:** 2026-08-18

**Durum:** Kullanıcı tarafından onaylandı

**Kapsam:** `rotori-mobile` içindeki plan görüntüleyicinin Biletler sekmesi, bilet ekleme/düzenleme akışı ve cihaz içi bilet görseli saklama katmanı

## 1. Problem

Mevcut Biletler sekmesi, geniş boş bir yüzey üzerinde tek satırlı kartlar gösteriyor. Bilet ekleme ise ad, bağlantı ve satın alma durumundan oluşan bir `AlertDialog`. Bu yapı:

- sıradaki bileti ve QR erişimini öne çıkarmıyor;
- satın alınmış biletlerle henüz satış bekleyen biletleri yeterince ayırmıyor;
- ekran görüntüsü veya bilet fotoğrafından ekleme akışı sunmuyor;
- bilinmeyen bilet formatlarından hangi bilgilerin çıkarılabileceğini güvenli biçimde yönetmiyor;
- mobilde doğal bir Apple sheet ve doğrudan manipülasyon hissi vermiyor.

## 2. Hedefler

1. Biletleri bir liste kaydı yerine kullanıcının yanında taşıdığı dijital cüzdan gibi hissettirmek.
2. Sıradaki hazır bileti, tarih/saat bilgisini ve QR erişimini ilk bakışta göstermek.
3. Satın alınmış, satış bekleyen ve eksik bilgi taşıyan biletleri açıkça ayırmak.
4. Galerideki ekran görüntüsü veya bilet fotoğrafını ve kamerayla çekilen görseli ekleme kaynağı yapmak.
5. Görselden çıkarılan bilgileri sabit alan varsaymadan, dinamik adaylar ve açık kullanıcı onayıyla kaydetmek.
6. Bilet görselini ve ham tarama verisini buluta göndermeden cihazda saklamak.
7. Mevcut plan ve bilet kayıtlarını geriye dönük uyumlu biçimde açmak.
8. Alt gezinme çubuğunu tüm bilet akışında görünür ve kararlı tutmak.

## 3. Kapsam Dışı

- Bilet görsellerinin cihazlar arasında senkronizasyonu.
- Görselin OpenAI veya başka bir harici yapay zekâ servisine gönderilmesi.
- Satın alma durumunun otomatik belirlenmesi.
- Kullanıcı onayı olmadan tarih, saat, rezervasyon kodu veya başka bir alanın kaydedilmesi.
- İlk sürümde PDF içe aktarma. Galeri/kamera kaynaklı JPG, PNG ve platformun sağladığı uyumlu resim biçimleri desteklenir.
- Harici satıcılardan otomatik bilet satın alma veya rezervasyon değiştirme.

## 4. Tasarım Yönü: Rotori Wallet

### 4.1 Liste ekranı

Biletler sekmesi, içerik alanında büyük `Biletler` başlığı ve sağ üstte dairesel `+` düğmesiyle açılır. Üst durum özeti örneğin `3 bilet · 2 hazır · sıradaki 3 gün sonra` biçimindedir; bilgi yoksa ilgili parça gösterilmez.

Liste hiyerarşisi:

1. **Sıradaki hazır bilet:** Büyük Wallet kartı. Tarih, şehir, bilet adı, giriş saati, kişi sayısı mevcutsa gösterilir. QR/görsel düğmesi kartın sağ altında doğrudan erişim sağlar.
2. **Diğer hazır biletler:** Daha kompakt, yatay Wallet kartları. Büyük kartı tekrar ederek ekranı ağırlaştırmaz.
3. **Hazırlanıyor:** Satış tarihi beklenen, rezervasyon bekleyen veya eksik bilgili biletler Apple `inset-grouped` liste içinde gösterilir.

Renk bilet türünü anlatır; durum yalnız renkle anlatılmaz. `Hazır`, `Satışa 7 gün`, `Eksik bilgi` gibi metin ve simge birlikte kullanılır. Kart türleri arasında aynı anlamdaki aksiyon aynı yerde bulunur.

Bilet kartına dokunmak detay/düzenleme sheet'ini açar. QR/görsel düğmesine dokunmak bilet görselini büyütür. Hazır bilet yoksa boş durum, kısa açıklama ve birincil `Bilet ekle` aksiyonu gösterilir.

### 4.2 Ekleme sheet'i

`+` veya boş durum aksiyonu, ekranın altından kaynağına bağlı ve sürüklenebilir bir bottom sheet açar. Sheet parmağı bire bir izler, sunum değerinden devam eder ve kapandığı yoldan geri döner. Azaltılmış hareket tercihinde kayma yerine kısa çapraz solma kullanılır.

İlk seviye aksiyonlar:

1. **Bilet görseli ekle** — birincil aksiyon.
2. **Plandan seç** — mevcut etkinlik veya şehir geçişini bilete bağlar.
3. **Elle gir** — görselsiz, manuel bilet oluşturur.

`Bilet görseli ekle` seçilince platforma tanıdık kaynak menüsü açılır:

- `Fotoğraflardan seç` — ekran görüntüsü ve bilet fotoğrafı.
- `Kamerayla tara` — yeni fotoğraf çekimi.
- `Vazgeç`.

Fotoğraf veya kamera izni yalnız kullanıcı ilgili aksiyona dokunduğunda istenir. İzin reddedilirse kullanıcı manuel girişe veya ayarlara yönlendirilir; akış kapanmaz.

### 4.3 Dinamik kontrol ekranı

Görselin içeriği önceden bilinemez. Bu nedenle kontrol ekranı sabit ve boş bir form çizmez. Tarama sonucu `aday bilgiler` üretir ve yalnız bulunan adayları gösterir.

Olası aday türleri:

- bilet/etkinlik adı;
- tarih;
- saat veya giriş aralığı;
- mekân/şehir;
- rezervasyon ya da onay kodu;
- koltuk, kapı veya bölüm;
- kişi sayısı;
- QR içeriği veya bağlantı.

Kurallar:

- Bir aday düzenlenebilir, silinebilir veya onaylanabilir.
- Birden fazla tarih/saat bulunursa sistem seçim ister; sessizce tahmin yapmaz.
- Düşük güvenli adaylar sayısal yüzde yerine `Kontrol et` durumu taşır.
- Bulunmayan alanlar hiç çizilmez; `Ayrıntı ekle` ile kullanıcı yeni alan ekleyebilir.
- `Satın alındı` durumu her zaman kullanıcı tarafından seçilir.
- Hiç aday bulunamazsa görsel korunur, yalnız bilet adı zorunlu tutulur ve manuel ayrıntılar açılır.
- Görsel, ham OCR metni veya QR içeriği kullanıcı kaydı onaylamadan kalıcı bilete bağlanmaz.

## 5. Bileşen Sınırları

Yeni bilet arayüzü, büyümüş `plan_viewer_screen.dart` içine eklenmek yerine odaklı bileşenlere ayrılır:

- `TicketWalletView`: liste hiyerarşisi, boş durum ve `+` aksiyonu.
- `TicketWalletCard`: büyük sıradaki bilet sunumu.
- `TicketCompactCard`: diğer hazır biletler.
- `TicketPendingGroup`: satış/rezervasyon/eksik bilgi listesi.
- `TicketAddSheet`: kaynak seçimi ve platform izin akışı.
- `TicketImportReview`: dinamik aday bilgilerin kullanıcı tarafından doğrulanması.
- `TicketDetailSheet`: mevcut bileti görüntüleme, düzenleme, görseli yeniden bağlama ve silme.
- `TicketImportController`: geçici dosya, cihaz içi tarama, aday üretme, onay ve iptal yaşam döngüsü.
- `TicketLocalMediaStore`: platformdan bağımsız yerel medya sözleşmesi.
- `TicketTextExtractor` ve `TicketQrExtractor`: cihaz içi çıkarma arayüzleri.

Plan görüntüleyici yalnız seçili `Trip`, ekleme/düzenleme callback'leri ve paleti aktarır. Medya dosyası işlemleri UI bileşenlerinin içine dağılmaz.

## 6. Veri Modeli

### 6.1 Bilinen alanlar

Takvim ve rota davranışını etkileyen mevcut alanlar korunur: `label`, `kind`, `visitDate`, `entryTime`, `bookingOpens`, `purchased`, bağlantılı etkinlik/geçiş ve süre alanları.

### 6.2 Yerel medya referansı

`Ticket` içine cihazdan bağımsız, opak bir `localMediaRef` eklenir. Bu değer:

- iOS/Android'de uygulama destek klasöründeki dosyayı;
- web önizlemesinde tarayıcıya özel IndexedDB blob kaydını

çözen yerel medya adaptörüne verilir. Plan JSON'u mutlak dosya yolu veya base64 görsel taşımaz.

### 6.3 Onaylanmış ek ayrıntılar

Sabit şemaya uymayan fakat kullanıcının saklamak istediği bilgiler için sıralı `TicketDetail` kayıtları kullanılır:

```text
TicketDetail
- id
- semanticKey?   // seat, gate, confirmationCode gibi bilinen isteğe bağlı anlam
- label          // kullanıcıya gösterilen/düzenlenebilen ad
- value
```

Bilinen tarih/saat gibi alanlar canonical `Ticket` alanlarına yazılır. Ek bilgiler `confirmedDetails` içinde kalır. Ham OCR metni yeni akışta plan JSON'una yazılmaz.

### 6.4 Geriye dönük uyumluluk

Mevcut `imageDataUrl` kayıtları okunmaya devam eder. Uygulama ilk uygun açılışta görseli yerel medya deposuna aktarır ve sonraki başarılı plan kaydında `localMediaRef` kullanır. Aktarım başarısızsa eski görsel gösterilmeye devam eder; veri sessizce silinmez.

## 7. Yerel Dosya Yaşam Döngüsü

1. Seçilen/çekilen görsel önce uygulamanın geçici alanına kopyalanır.
2. OCR ve QR çıkarma geçici kopya üzerinde cihazda çalışır.
3. Kullanıcı kontrol ekranını onaylarsa dosya `tickets/<planId>/<ticketId>/` mantıksal alanına atomik biçimde taşınır.
4. Plan kaydı başarılı olduktan sonra eski görsel varsa silinir.
5. Kullanıcı vazgeçerse geçici dosya hemen silinir.
6. Uygulama başlangıcında 24 saatten eski, hiçbir bilete bağlı olmayan geçici dosyalar temizlenir.
7. Bilet silinince bağlı yerel medya dosyası, plan değişikliği başarıyla kaydedildikten sonra silinir.

Orijinal görsel QR okunabilirliğini bozacak şekilde sıkıştırılmaz. Liste için ayrı, küçük bir thumbnail üretilebilir; detay görünümü orijinali açar.

## 8. Veri Akışı

```text
Galeri/Kamera
  → geçici yerel kopya
  → cihaz içi OCR + QR
  → dinamik aday bilgiler
  → kullanıcı kontrolü
  → kalıcı yerel medya referansı
  → UpsertTicket / PlanEditSession
  → başarılı plan kaydı
```

Plandan seçme akışında görsel zorunlu değildir. Seçilen etkinlik/geçiş mevcut tarih, saat ve bağlantı alanlarını başlangıç değeri olarak sağlar; kullanıcı yine kontrol eder.

## 9. Hata ve Kenar Durumları

- **İzin reddedildi:** Kısa açıklama, `Ayarlara git` ve `Elle gir` aksiyonları.
- **Görsel okunamadı:** Görsel korunur; manuel alanlar açılır.
- **Hiç bilgi bulunamadı:** Hata ekranı yerine `Bilgi bulunamadı, bileti elle tamamla` durumu.
- **Çelişen tarih/saat:** Aday seçenekleri gösterilir; otomatik seçim yapılmaz.
- **Yerel dosya kayıp:** Bilet kartı ve metin alanları kalır, `Görseli yeniden ekle` sunulur.
- **Plan kaydı başarısız:** Kalıcı dosya referansı bilete geçirilmez; kullanıcı tekrar deneyebilir, geçici dosya oturum boyunca korunur.
- **Kullanıcı iptal etti:** Yarım bilet oluşmaz, geçici dosya silinir.
- **Çok uzun metin/Büyük Yazı:** Kart yüksekliği büyüyebilir; başlık en fazla iki satır, ikincil bilgi yeniden akar.
- **Uzun bilet listesi:** Yalnız sıradaki hazır bilet büyük karttır; diğerleri kompakt ve sanallaştırılabilir listedir.

## 10. Apple Tasarım ve Erişilebilirlik İlkeleri

- Sistem yazı tipi, boyuta göre sıkılaşan başlık tracking'i ve Dynamic Type.
- En az 44×44 pt dokunma hedefleri.
- Durumların renk + simge + metinle birlikte anlatılması.
- Sheet'in sürükleme sırasında parmağı bire bir izlemesi ve kesintiye açık olması.
- Açılış/kapanışın aynı uzamsal yolu izlemesi.
- Varsayılan hareketin kritik sönümlü olması; yalnız kullanıcı momentumu taşıyan sheet bırakışında hafif yay.
- `Reduce Motion` için kayma yerine kısa opacity geçişi.
- Ekran okuyucuda kartın tek anlamlı özet olarak okunması; QR ve düzenleme aksiyonlarının ayrı etiketlenmesi.
- Alt gezinme çubuğunun liste, ekleme ve geri dönüş boyunca kaybolmaması veya yer değiştirmemesi.

## 11. Test Stratejisi

### Widget testleri

- Boş durumda açıklama ve `Bilet ekle` aksiyonu görünür.
- Sıradaki hazır bilet büyük, diğer hazır biletler kompakt, bekleyenler ayrı gruptadır.
- Durumlar yalnız renk üzerinden verilmez.
- `+` bottom sheet'i açar ve galeri/kamera/plandan seç/elle gir aksiyonlarını gösterir.
- Dinamik kontrol ekranı yalnız bulunan adayları gösterir.
- Birden fazla tarih/saat adayı kullanıcı seçmeden kaydedilmez.
- `Satın alındı` varsayılan olarak otomatik işaretlenmez.
- Hiç bilgi bulunamadığında manuel devam mümkündür.
- Büyük yazı boyutunda taşma olmaz; alt gezinme görünür kalır.

### Birim testleri

- OCR/QR sonucu `TicketImportCandidate` kayıtlarına güvenli biçimde dönüştürülür.
- Bilinen adaylar canonical `Ticket` alanlarına, diğerleri `confirmedDetails` içine yazılır.
- İptal geçici dosyayı temizler.
- Başarılı kayıt dosyayı kalıcı alana taşır.
- Başarısız plan kaydı eski medyayı silmez.
- Kayıp dosya güvenli `yeniden ekle` durumuna dönüşür.
- Eski `imageDataUrl` kayıtları kayıpsız yerel medyaya aktarılır.

### Platform testleri

- iOS fotoğraf seçici ve kamera izinlerinin yalnız etkileşim anında istenmesi.
- Android fotoğraf seçici/kamera davranışı ve uygulama özel depolama.
- Web önizlemesinde IndexedDB yerel medya adaptörü ve yenileme sonrası erişim.

## 12. Kabul Ölçütleri

1. Kullanıcı ekran görüntüsünü galeriden seçip bilet olarak kaydedebilir.
2. Kullanıcı kamerayla fotoğraf çekip aynı kontrol akışına girebilir.
3. Görsel ve ham tarama verisi ağ üzerinden gönderilmez.
4. Bulunan bilgiler dinamik, düzenlenebilir ve kullanıcı onaylıdır.
5. Tarama başarısızlığı manuel bilet eklemeyi engellemez.
6. Sıradaki bilet ve QR/görsel erişimi ilk ekranda belirgindir.
7. Satış bekleyen biletler hazır biletlerden açıkça ayrılır.
8. Bilet ekleme ve düzenleme sırasında alt gezinme kaybolmaz.
9. Mevcut biletler veri kaybı olmadan açılır.
10. İptal, hata ve silme yolları sahipsiz yerel dosya bırakmaz.
