# Rotori Rota Deneyimi Refactor Planı

Tarih: **2026-08-10**
Durum: **Faz 0–4 tamamlandı; Faz 5 kısmi**

## 1. Hedef

Rotori'nin mevcut rota algoritmasını yeniden yazmadan, ürettiği sonucu ilk kez
Japonya'ya giden bir kullanıcının planlama sırasında anlayabileceği ve sahada
uygulayabileceği bir yolculuk deneyimine dönüştürmek.

Başarı ölçütü:

> Kullanıcı bir günü açtığında sıradaki durağı, ne zaman çıkacağını, hangi
> ulaşım türünü kullanacağını, yaklaşık süre/yürüyüş/aktarma/maliyeti ve verinin
> tahmini olup olmadığını başka bir ekranda araştırmadan anlayabilmelidir.

## 2. Değişmeyecek algoritma sözleşmeleri

Aşağıdaki davranışlar refactor boyunca korunur ve regresyon testleriyle
kilitlenir:

1. Rota sırasını AI değil yönlü `RouteMatrix` ve saf Dart optimizer belirler.
2. Varsayılan `beamWidth = 6` kalır; ölçüm olmadan artırılmaz veya azaltılmaz.
3. Sabit saat, rezervasyon, çalışma saati, minimum süre ve gün sonu kuralları
   hard constraint olarak kalır.
4. `mustDo` ve sabit aktiviteler otomatik düşürülemez.
5. Aynı girdi + aynı matris + aynı profil aynı semantik sonucu üretir.
6. Balanced / Fastest / Least Walking / Cheapest profil ayrımı korunur.
7. `RouteOptimizationValidator` geçmeden sonuç kaydedilemez.
8. Değişiklik yalnız açık kullanıcı onayından sonra kalıcılaştırılır.
9. AI yalnız POI keşfi/açıklama sınırında kalır; sıra ve ulaşım modu seçmez.
10. Tahmini matris sonucu gerçek sağlayıcı verisi gibi gösterilmez.

Bu sözleşmelerden biri değişecekse önce benchmark çalıştırılır, karar
`DECISIONS.md`'ye eklenir ve eski/yeni sonuç ölçülür.

## 3. Mevcut sorunlar

- Optimizer ayrıntılı `RouteLeg` üretmesine rağmen viewer yalnız durakları
  gösteriyor; ulaşım ayakları kullanıcıya taşınmıyor.
- `RouteLeg`, matristen gelen hat/yön ve istasyon karmaşıklığı bilgisini
  kaybediyor.
- Optimize edilen plan kalıcılaştırılırken aktivite sırası/saatleri saklanıyor,
  rota ayağı snapshot'ı saklanmıyor.
- Üretim route gateway'i kapalı; koordinat fallback'i tahmini olmasına rağmen
  kullanıcı dili bu ayrımı yeterince görünür yapmıyor.
- Uçuş/otel bilinmeden üretilen yer tutucular gerçek rezervasyon gibi
  algılanabiliyor.
- Şehir geçişi ulaşım modu ve bileti tek akışta düzenlenemiyor.
- Biletler boş durumu kullanıcıyı bir sonraki eyleme yönlendirmiyor.
- Plan oluşturma tercihleri sınırlı ve çelişen diyet seçimlerini kabul ediyor.

## 4. Hedef katmanlar

```text
Plan girdileri + açık varsayımlar
        ↓
TripActivityAssignmentEngine             (korunur)
        ↓
RouteMatrix → BeamSearch optimizer        (korunur)
        ↓
RouteOptimizationValidator                (korunur)
        ↓
RouteLeg → RouteExecutionLeg adaptörü      (yeni, saf Dart)
        ↓
Ön izleme: sıra + ulaşım ayakları + veri güveni
        ↓ kullanıcı onayı
Versioned route snapshot + plan persistence
        ↓
Viewer: Şimdi / Sonraki / Nasıl gidilir / Bilet
```

`RouteExecutionLeg` sunum sözleşmesidir; skor üretmez ve optimizer kararını
değiştirmez. UI metinleri l10n katmanında üretilir.

## 5. Fazlar

### Faz 0 — Baseline ve belge doğruluğu

- [x] Korunacak algoritma sözleşmelerini yaz.
- [x] Tek bir `route_algorithm_contract_test.dart` kapısında kritik
      invariant'ları sabitle.
- [x] Mevcut rota harness kalite kapısını refactor baseline'ı olarak çalıştır.
      100 × 4 ürün benchmark'ı Faz 1 optimizer davranışı değişirse yeniden
      ölçülecek; bu teslimatta karar/skor değişmedi.
- [x] Mimari belgelerde eski 8-adımlı planner tanımını güncel 3-adımlı akışla
      değiştir.

Kabul: Çekirdek kod değişmeden hedefli testler yeşil.

### Faz 1 — Kayıpsız rota çıktısı ve sunum adaptörü

- [x] `RouteLeg` içine opsiyonel `lineId`, `directionId` ve
      `complexityPenalty` alanlarını kayıpsız taşı.
- [x] Saf Dart `RouteExecutionLeg` / builder ekle.
- [x] Başlangıç→durak, durak→durak ve son durak→otel dönüş ayaklarını ayır.
- [x] Süre, yürüyüş, bekleme, aktarma, maliyet, hat/yön ve
      reliable/estimated durumunu sunum modeline aktar.
- [x] Adapter ve geriye uyumluluk testlerini ekle.

Kabul: Aynı optimizer sırası/skoru/metrikleri korunur; yalnız çıktı daha fazla
bilgi taşır.

### Faz 2 — Doğru plan girdisi ve varsayımlar

- [x] Uçuş/otel bilgisi yoksa ilgili kalemleri açıkça `taslak` işaretle.
- [x] Tarihi belirsiz öneride yıl, mevsim gerekçesi ve değiştirilebilirlik
      görünür olsun.
- [x] Plan oluşturulmadan önce kısa bir “Bu varsayımlarla hazırlıyorum” özeti
      ve düzeltme bağlantıları göster.
- [x] Varsayımlar eski plan JSON'larını bozmayan opsiyonel/versioned alanlarla
      saklansın.

Kabul: Uygulama bilmediği havalimanı, otel veya rezervasyonu gerçekmiş gibi
sunmaz.

### Faz 3 — Günlük ulaşım ayakları

- [x] Optimizasyon ön izlemesinde durakların arasına ulaşım kartları ekle.
- [x] Viewer'da “çıkış saati · süre · mod · yürüyüş · aktarma · ücret” göster.
- [x] Tahmini ayakları görünür rozet ve açıklamayla ayır.
- [x] Gerçek sağlayıcı varsa hat/yön; yoksa yalnız güvenilir şekilde bilinen
      genel ulaşım modunu göster.
- [x] Günlük Google Maps geçişi ikincil kaçış yolu olarak kalsın.

Kabul: Kullanıcı her ardışık durak arasında nasıl ilerleyeceğini anlayabilir;
harita üzerindeki düz çizgi gerçek navigasyon gibi sunulmaz.

### Faz 4 — Şehir geçişi ve bilet akışı

- [x] Şehir geçişi kartında Shinkansen / tren / otobüs / taksi / uçak seçimi.
- [x] Seçim `PlanScheduleEngine` üzerinden kalıcılaştırılır.
- [x] Aynı karttan bilet ekle, görüntüle ve düzenle.
- [x] Biletler boş durumuna birincil CTA ve açıklama ekle.
- [x] Bilet ile bağlı aktivite/geçiş arasında çift yönlü bağlantı kur.

Kabul: Kullanıcı bir şehir geçişini ve biletini tek görev akışında tamamlar.

### Faz 5 — Plan oluşturma kişiselleştirmesi

- [ ] Tempo, ilgi alanı, yolcu tipi, erişilebilirlik ve yürüme toleransı.
- [x] Çelişen diyet tercihleri için domain seviyesinde uyumluluk kuralları.
- [ ] Must-see seçimini plan üretiminden önce veya özet adımında görünür yap.
- [ ] Üretilen plan için kısa “neden böyle” açıklaması.

Kabul: Tercihler optimizer'a açık ve test edilebilir kısıt/öncelik olarak
gider; serbest metin veya UI sezgisi olarak kalmaz.

### Faz 6 — Gerçek rota gateway'i ve kalıcı cache

- [ ] Sağlayıcı seçimi ve Edge Function uygulaması.
- [ ] Anahtarlar yalnız backend'de.
- [ ] Versioned cihaz cache'i; yön/profil/zaman dilimi anahtarı korunur.
- [ ] Büyük istasyon metadata'sı, çıkış/aktarma tamponu ve veri yaşı.
- [ ] Provider hata oranı, cache hit ve fallback telemetry'si.

Kabul: Sağlayıcı kesintisinde plan kaybolmaz; stale/estimated veri dürüstçe
etiketlenir.

### Faz 7 — Saha modu

- [ ] “Şimdi / sıradaki / ne zaman çıkmalıyım?” odaklı günlük görünüm.
- [ ] Gecikmede kullanıcı onaylı yeniden hesaplama.
- [ ] Offline snapshot ve son güvenilir rota verisi.
- [ ] Konum izinleri yalnız kullanım anında ve pil dostu modelle.

Kabul: Kullanıcı gezi günü ana ekrandan bir sonraki eylemi tek bakışta görür.

## 6. Test kapıları

Her fazda:

1. `flutter analyze` sıfır hata.
2. Hedefli domain/controller/widget testleri.
3. Algoritma sözleşme testi.
4. Rota harness hard violation / duplicate / must-do / return kapıları.
5. TR/EN metin doğrulaması.
6. iPhone dar ekran önizlemesi.
7. Eski plan JSON fixture'larının açılması.

Faz 1, 3 veya 6 optimizer sonucunu etkilerse ek olarak aynı seed ile 100 × 4
benchmark eski/yeni karşılaştırması zorunludur.

## 7. Risk yönetimi

- Kalıcı modele yeni alanlar ilk okumada opsiyonel olur; migration tamamlanana
  kadar eski planlar varsayılan değerle açılır.
- Route snapshot optimizer'ın doğru kaynağı değildir; matris veya aktivite
  hash'i değişince geçersiz sayılır.
- UI, `isEstimated` verisini gizleyemez.
- Refactor sırasında `day_optimizer.dart` fallback'i kaldırılmaz; gerçek
  gateway kalite kapısı geçmeden davranış değişmez.
- Mevcut kullanıcı değişiklikleri ayrı tutulur; sosyal otomasyon dosyaları ve
  yerel launch ayarları bu çalışma kapsamında değildir.

## 8. 2026-08-10 uygulama durumu

Tamamlanan ürün dilimi:

1. Algoritma davranış sözleşmesi ve Faz 1 kayıpsız sunum adaptörü.
2. Plan varsayımları için geriye uyumlu `PlanAssumptions` schema v1 ve
   oluşturma öncesi düzenlenebilir özet.
3. Ön izleme ve kaydedilmiş günlük timeline içinde görünür ulaşım kartları.
4. Aktivite/matris değişince geçersizleşen opsiyonel `RouteExecutionSnapshot`
   schema v1.
5. Şehir geçişi modu ile bağlı biletin tek `PlanScheduleEngine` hattından
   düzenlenmesi.
6. Diyet seçimlerindeki vegan/vejetaryen–et çelişkilerinin domain katmanında
   giderilmesi.

Doğrulama: değişen domain/controller/widget paketi **94/94**, rota harness
**15/15** başarılı; değişen dosyaların analizi temizdir. Proje genelinde bu
refactor dışındaki eski **17** uyarı/bilgi devam eder. Dar iPhone web ön
izlemesinde varsayım özeti, şehir geçişi, bilet ve rota kartları görsel olarak
kontrol edilmiştir.

Bilerek açık kalanlar: gerçek route provider/Edge Function, kalıcı cihaz
matrix cache'i, istasyon metadata'sı, Faz 5'in tempo/yolcu/erişilebilirlik
girdileri ve Faz 7 saha modu. Bunlar tahmini veriyi gerçekmiş gibi gösterecek
geçici uygulamalarla kapatılmayacaktır.
