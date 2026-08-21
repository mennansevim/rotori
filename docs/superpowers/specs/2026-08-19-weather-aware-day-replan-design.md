# Hava Koşullarına Göre Günlük Rota Yenileme

## Amaç

Rota oluşturulduktan sonra yağmur, fırtına veya aşırı sıcaklık gibi koşullar
ortaya çıktığında kullanıcıya o günün planını hava durumuna göre yeniden
düzenleme önerisi sunmak. Kullanıcı öneriyi inceleyip onaylarsa yalnızca
seçili günün planı replace edilir; diğer günler değişmez.

## Kullanıcı akışı

Her gün kartının altında `Havaya göre düzenle` aksiyonu bulunur. Kullanıcı bu
aksiyona bastığında uygulama seçili günün destinasyonu, güncel/tahmini hava
verisi, durakları, saatleri ve kilit durumlarını rota inceleme servisine
gönderir.

Servis mevcut durak kümesi içinde hava koşullarına daha uygun bir sıra önerir.
Öneri ekranı mevcut ve önerilen sıralamayı, kısa AI gerekçelerini ve hava
özetini gösterir. Kullanıcı `Planı uygula` dediğinde yalnız seçili günün
durak sırası mevcut planla atomik biçimde değiştirilir. Uygulama sonrasında
tek kullanımlık `Geri al` aksiyonu önceki gün snapshot'ını geri yükler.

AI önerisi doğrudan uygulanmaz. Servis yeni durak ekleyemez, durak silemez,
başka güne taşıyamaz ve kilitli durakların konumunu değiştiremez. İstemci de
aynı kuralları bağımsız doğrular; doğrulama başarısızsa plan değişmeden kalır.

## Veri akışı ve sınırlar

1. Open-Meteo mevcut koşullar ile günlük tahmini sağlar. Destinasyon bazlı
   çağrı mevcut forecast provider/cache yapısı üzerinden yeniden kullanılır.
2. Gün kartı, `DayForecast` verisini ve günün `DayPlan` verisini aynı tarihten
   besler; hava ekranı ve gün kartı arasında farklı veri gösterilmez.
3. `review-route` Edge Function, mevcut weather-aware route review sözleşmesi
   genişletilerek seçili gün için aday sıra ve en fazla üç kısa not döndürür.
4. LLM anahtarı istemciye taşınmaz. Timeout veya ağ/JSON hatasında kullanıcıya
   hata ve tekrar deneme gösterilir; plan sessizce değiştirilmez.
5. Onay sonrası kayıt mevcut `PlanEditSession` komutları ve repository save
   hattı üzerinden yapılır. Geri alma snapshot'ı yalnız kullanıcı onayından
   hemen önceki seçili günü kapsar.

Tahmin ufku dışındaki tarihler için AI kesin hava iddiasında bulunmaz. Hava
verisi yoksa aksiyon devre dışı veya açıklamalı hata durumunda kalır.

## UI davranışı

- Gün akışındaki her günün altında kısa `Havaya göre düzenle` butonu görünür.
- Yağış veya aşırı sıcaklık varsa buton bağlama göre `Yağmura göre düzenle`
  veya `Hava koşullarına göre düzenle` etiketi kullanabilir.
- Yüklenirken buton tekil gün için devre dışı kalır ve ilerleme göstergesi
  gösterir.
- Önizleme sheet/card'ı mevcut planı ve öneriyi karşılaştırmalı sunar.
- Onaydan sonra gün kartı yeni sırayı gösterir ve geri alma snackbar'ı çıkar.
- Başarısız öneri veya reddetme mevcut planı değiştirmez.

## Test ve doğrulama

- Open-Meteo current/daily parse ve eksik veri davranışı için birim testleri.
- Edge Function sözleşmesi için weather input, kilitli durak ve aynı durak
  kümesi doğrulama testleri.
- Gün kartında her gün için aksiyon, yükleniyor, hata, reddetme ve önizleme
  widget testleri.
- Onay sonrası yalnız seçili günün değiştiğini; diğer günlerin, kilitli
  durakların ve geri alma snapshot'ının korunduğunu test et.
- Hedefli Flutter testleri, `flutter analyze --no-pub`, Edge Function type
  check ve web preview görsel kontrolü çalıştır.

## Kapsam dışı

- AI'ın yeni destinasyon keşfetmesi veya planı başka güne taşıması.
- Arka planda sürekli konum/hava izleme.
- Kullanıcı onayı olmadan otomatik plan değişikliği.
- Tüm rotayı tek butonla yeniden planlama.
