# Rotori Rota Optimizasyonu — Teknik Not

Son güncelleme: **2026-07-30**

## Amaç ve mevcut sistem analizi

Eski `mobile/lib/domain/day_optimizer.dart`, koordinatı bulunan esnek
aktiviteleri nearest-neighbor ile sıralıyor ve geçişleri sabit 30 dakika
varsayıyordu. Bu yaklaşım gerçek kapıdan kapıya süreyi, yönlü rota farkını,
aktarma sayısını, büyük istasyon karmaşıklığını ve ulaşım maliyetini bilmiyor.

Mevcut `PlanScheduleEngine` ise farklı bir sorumluluğu doğru biçimde taşıyor:
kullanıcı düzenlemelerini immutable komutlarla uygular, sabit aktiviteleri
korur, zaman çakışmasını engeller, etkilenen günleri yeniden saatler ve
undo/persistence akışını yönetir. Yeni rota motoru bu katmanı değiştirmez.

Yeni ayrım:

```text
TimelineItem + kullanıcı tercihi
        ↓ adapter
TripLocation + OptimizationActivity
        ↓
RouteMatrixRepository
        ↓
backend/Edge Function kaynaklı yönlü RouteMatrix
        ↓
BeamSearchItineraryOptimizer
        ↓
PlanOptimizationController ön izlemesi
        ↓ kullanıcı onayı
PlansRepository.save
```

## Eklenen katmanlar

### Rota matrisi

`mobile/lib/domain/route_matrix.dart`:

- `walking`, `train`, `metro`, `bus`, `taxi`, `shinkansen`,
  `regionalTrain`
- yönlü `RouteMatrixEntry`
- kapıdan kapıya süre, yürüyüş, bekleme, aktarma, yen maliyeti, güvenilirlik,
  hat/yön ve karmaşıklık alanları
- Balanced, Fastest, Least Walking ve Cheapest profilleri
- sağlayıcıdan bağımsız `RouteMatrixRepository`
- deterministik test repository'si

A→B verisi B→A yerine kullanılamaz. Koordinatlar ulaşım süresi üretmek için
kullanılmaz.

### Deterministik optimizasyon

`mobile/lib/domain/itinerary_optimizer.dart`:

- varsayılan beam width: 6
- artımlı route state; her genişlemede tüm rota yeniden hesaplanmaz
- sabit aktiviteler arasında uygulanabilir sıra araması
- açılış/kapanış, minimum süre, fixed time, gün sınırı ve otele dönüş için
  hard pruning
- gerçek rota seçenekleri arasında profile göre ulaşım modu seçimi
- cluster re-entry, yön tersine dönüş, aynı hatta ters yön, aktarma,
  yürüyüş, bekleme, maliyet ve karmaşıklık cezaları
- arama sonrası sınırlı swap/move local improvement
- typed failure ve yapılandırılmış aktivite/leg/metrik/warning çıktısı

Başlangıç maliyet ağırlıkları tek `OptimizationWeights` modelinde tutulur.
Uygulanamaz rota yalnızca yüksek skor almaz; elenir.

### Backend, cache ve fallback

`RouteMatrixBackendGateway` API anahtarı kabul etmez. Gerçek HTTP veya
Supabase Edge Function taşıyıcısı bu interface'i daha sonra uygular. Şu an
güvenli varsayılan `UnavailableRouteMatrixBackendGateway`'dir.

Fallback sırası:

1. Taze birincil/alternatif cache
2. Birincil backend
3. Alternatif backend
4. Eski cache; bütün seçenekler `isEstimated=true`
5. Typed unavailable; koordinat yalnızca ön eleme için kullanılabilir

Cache anahtarı yönü, dört ondalığa yuvarlanmış koordinatları, modu, gün tipini,
zaman dilimini, tercih profilini ve sağlayıcıyı kapsar. Başlangıç TTL'leri:

- yürüyüş: 30 gün
- tren/metro/Shinkansen/bölgesel tren: 7 gün
- otobüs: 3 gün
- taksi: 3 saat

İlk sürüm cache'i bellek içidir; uygulama yeniden başladığında kaybolur.

## Flutter/Riverpod entegrasyonu

`PlanOptimizationController`:

- mevcut `TimelineItem` modelini kullanır; ikinci bir kalıcı aktivite modeli
  oluşturmaz
- koordinat eksikliğini route gateway çağrısından önce reddeder
- rota matrisini alır ve optimizer'ı çalıştırır
- eski ve yeni toplam ulaşım/yürüyüş/aktarma/maliyet özetini üretir
- optimize planı ön izleme olarak tutar
- yalnızca `confirm()` çağrısında kalıcılaştırır
- `discard()` ile değişiklik yapmadan kapanır
- `planId + planVersion + activityHash + profile + matrixVersion` anahtarıyla
  tekrar optimizasyonunu önler

Üretim gateway'i eklenene kadar provider typed unavailable döndürür. Test ve
preview ortamları repository/gateway provider override kullanır.

Viewer gün kartındaki “Rotayı optimize et” eylemi bu state'i görünür bir
bottom sheet'e bağlar. Kullanıcı dört profilden birini seçebilir; Önce/Sonra
ulaşım, yürüyüş, aktarma ve maliyet metriklerini görür. Vazgeç planı
değiştirmez; “Rotayı uygula” repository, edit session ve home widget
snapshot'ını birlikte yeniler. Konum veya güvenilir rota verisi eksikse plan
korunur. Web QA girişinde yalnız tasarım doğrulaması için açıkça tahmini olarak
işaretlenmiş deterministik fake matrix bulunur; üretim provider'ına sızmaz.

## AI kullanım ve maliyet politikası

Normal akış:

```text
Route API → deterministic optimizer → validation → preview
```

AI varsayılan olarak çağrılmaz. Yalnızca kullanıcı açıklama istediğinde,
rota güveni eşik altındaysa, kritik uyarı/anomali varsa veya en iyi iki sonuç
çok yakınsa `CostOptimizedAiUsagePolicy` izin verebilir.

Koruyucular:

- model adları ve çıktı token sınırı config'tedir
- plan ve gün başına çağrı bütçesi vardır
- AI'a rota özeti, metrikler, warning'ler ve gerekli kullanıcı tercihi gider
- aktivite başına çağrı yoktur; gün tek batch'tir
- rota+metrik+tercih+promptVersion+model cache anahtarı kullanılır
- girdide olmayan aktiviteye referans veren çıktı reddedilir
- AI çıktısı rotayı doğrudan değiştiremez veya veritabanına yazamaz
- hata/timeout/invalid output deterministik rota nesnesini aynen korur

Gerçek AI repository'si bağlı olmadığı için mevcut sürümün planlama başına AI
maliyeti **sıfırdır**.

## Harita API maliyet analizi

Gerçek sağlayıcı fiyatı seçilmediğinden parasal tahmin yapılmaz. Çağrı hacmini
azaltan mevcut tasarım:

- aynı aktivite setini batch/matrix olarak gateway'e verir
- yön ve zaman dilimini cache anahtarında korur
- çok küçük koordinat farklarını dört ondalıkta birleştirir
- taze cache hit'te backend çağrısı yapmaz
- primary hata verirse alternate veya stale cache kullanır
- plan sürümü/aktivite hash'i değişmediyse optimizer sonucunu tekrar kullanır

Gerçek gateway aşamasında ölçülecek metrikler: matrix istek sayısı, cache hit
oranı, sağlayıcı başına başarı/hata, stale fallback sayısı, optimize süresi,
değerlendirilen/elenen state sayısı ve eski/yeni rota metrikleri. Loglara API
anahtarı veya hassas kullanıcı verisi yazılamaz.

## Test kapsamı

- Tokyo küme bütünlüğü
- Osaka güney→merkez→Umeda akışı
- 14:00 sabit restoran rezervasyonu ve gerekli taksi seçimi
- fixed/locked aktivite, kapanış, minimum süre ve gün sonu
- Balanced/Fastest/Least Walking/Cheapest davranışı
- yönlü matris ve fake repository
- cache anahtarı, TTL, hit ratio
- primary/alternate/stale/unavailable fallback
- AI policy, bütçe, cache, scope ve hata izolasyonu
- Riverpod ön izleme, açık onay ve sonuç cache'i

2026-07-30 doğrulaması: `flutter analyze` temiz, `flutter test` **418/418**
başarılı.

## Bilinen kısıtlar ve sonraki adımlar

1. Gerçek route backend/Edge Function ve sağlayıcı seçimi henüz yoktur.
2. Büyük Japonya istasyonu metadata/tampon normalizasyonu backend tarafında
   merkezi bir kaynak olarak eklenmelidir.
3. Rota ve ön izleme cache'i cihazda kalıcı değildir.
4. Viewer görünür karşılaştırma/onay sheet'ini kullanır; planner henüz eski
   yüzeyi kullanır.
5. Günler arası taşımada `PlanScheduleEngine` iki günü zamansal olarak
   optimize eder; iki günün coğrafi sonucunu tek atomik ön izlemede gösteren
   UI/controller genişletmesi henüz yoktur.
6. Gerçek sağlayıcı gelene kadar açılış saati ve istasyon kaynaklı süreler
   uydurulmaz; eksik rota typed unavailable olarak kalır.
