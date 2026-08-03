# Rota Optimizasyonu — İyileştirme ve Düzeltme Uygulama Planı

**Durum:** Uygulamaya hazır teknik plan  
**Hazırlanma tarihi:** 2026-08-03  
**İncelenen çıktı:** `route_opt_scenarios.json`  
**İncelenen koşum:** 100 senaryo, seed `20260803`, sentetik matris v1  
**Kapsam:** Test harness'i, saf Dart rota motoru, günler arası aktivite
ataması, maliyet modeli, çıktı şeması, ölçüm ve regresyon testleri

> Bu belge doğrudan bir uygulama görevi olarak kullanılmak üzere yazılmıştır.
> Aşağıdaki fazlar sırayla uygulanmalı; her faz kendi testleri yeşil olmadan
> sonraki faza geçilmemelidir.

---

## 1. Amaç

Mevcut `BeamSearchItineraryOptimizer` gün içi sıralamayı deterministik olarak
çözüyor; ancak 100 senaryoluk koşum aşağıdaki sorunları gösteriyor:

1. Test verisi gerçek dünyada kapalı olan yemek yerlerine akşam yemeği koyuyor.
2. Günler arası POI dağıtımı coğrafi ve zamansal uygunluk gözetmeden yapılıyor.
3. Tema parkı ayırma kuralı havuz yenilendiğinde atlanabiliyor.
4. `%100 feasible` sonucu aktivite düşürmeleri ve boş dönüş günleri nedeniyle
   gerçek başarıyı olduğundan iyi gösteriyor.
5. Aktivite düşürme kararı kullanıcı önceliğini ve başka güne taşıma seçeneğini
   dikkate almıyor.
6. Coğrafi kümeye geri dönüş ve uzun boşluk oranı yüksek.
7. JSON, baseline → beam search → local improvement farklarını göstermediği
   için algoritmanın gerçek kazancı ölçülemiyor.
8. Profil karşılaştırmaları aynı girdiler üzerinde yapılmıyor.
9. Maliyet birimleri kişi başı ve araç toplamı arasında karışıyor.
10. Sentetik matris yönlü kayıt üretse de değerleri gerçekte simetrik.

Hedef, yalnızca her günü “bir şekilde feasible” yapmak değildir. Hedef;
istenen aktiviteleri mümkün olduğunca koruyan, çalışma saatlerine uyan,
gereksiz geri dönüş ve boşluk üretmeyen, maliyeti tutarlı hesaplayan ve yaptığı
her iyileştirmeyi ölçülebilir biçimde açıklayan bir rota hattıdır.

---

## 2. Değişmez Mimari Kurallar

Uygulama sırasında aşağıdaki proje kararları korunmalıdır:

- Rota sırasını AI belirlemez. Karar, yönlü rota matrisi ve deterministik saf
  Dart motorundan gelir.
- AI varsa yalnızca açıklama/denetim yapabilir; rota, saat, mod veya düşürülen
  aktivite üzerinde mutasyon yapamaz.
- `mobile/lib/domain/` Flutter ve Supabase import etmez.
- Gerçek rota sağlayıcısının API anahtarı mobil uygulamaya girmez.
- Viewer/planner kullanıcı aktivitesini sessizce kaybetmez. Üretim akışında
  `allowActivityDropping` varsayılan olarak kapalı kalır.
- Aktivite düşürme açık olan harness/öneri akışlarında her kayıp yapılandırılmış
  gerekçeyle raporlanır.
- Sabit/rezervasyonlu aktivite hiçbir koşulda düşürülemez veya oynatılamaz.
- Yeni şema ve modeller geriye uyumlu okunmalıdır.

---

## 3. Ölçülen Başlangıç Değerleri

Bu değerler yeni koşumun karşılaştırma baseline'ıdır. Uygulama sonunda aynı
seed ile yeniden ölçülmelidir.

| Gösterge | Mevcut değer | Sorun |
|---|---:|---|
| Senaryo | 100 | — |
| Toplam gün kaydı | 1.168 | 100 tanesi boş dönüş günü |
| Gerçek rota günü | 1.068 | — |
| Sırası değişen gün | 726 (%68,0) | Baseline rastgele olduğu için kazanç değil |
| Taşıma açıklaması | 2.508 | 582'si öğle yemeği taşıması |
| Aktivite düşürülen gün | 365 (%34,2) | Düşürmesiz başarı düşük |
| Düşürmesiz feasible rota günü | 703 (%65,8) | Gerçek strict başarı |
| Tam günde düşürme | 293 / 715 (%41,0) | Çok yüksek |
| Düşürülen gezi POI oranı | %11,3 | 365 / 3.230 |
| Cluster'a geri dönüşlü gün | 670 (%62,7) | Toplam 857 re-entry |
| Kyoto re-entry | 317 / 337 (%94,1) | Yemek yeri + gün ataması etkisi |
| Bekleme > 90 dk | 252 gün (%23,6) | Transit ve idle karışık |
| Bekleme > 120 dk | 163 gün (%15,3) | Günler ciddi biçimde boş kalıyor |
| Warning | 0 | Sentetik veri riski görünmüyor |
| `fixed:true` aktivite | 0 | Envelope notuyla çelişiyor |
| Aynı POI'nin tekrarlandığı senaryo | 81 / 100 | Toplam 697 fazladan ziyaret |
| Yapay kahvaltı yürüyüşü | 1.746 dk | Aynı koordinata 3 dk leg |

### En sık düşürülen noktalar

| POI | Düşürme | Planlanma | Yaklaşık düşürme oranı |
|---|---:|---:|---:|
| Miyajima Itsukushima | 98 | 8 | %92,5 |
| Tenryu-ji | 31 | 58 | %34,8 |
| Universal Studios Japan | 28 | 67 | %29,5 |
| Horyu-ji | 21 | 24 | %46,7 |
| Kaiyukan Akvaryum | 18 | 59 | %23,4 |

### Profil gözlemleri

Mevcut sonuçlar farklı girdiler üzerinde üretildiği için profiller doğrudan
karşılaştırılamaz. Yalnız davranış sinyali olarak:

| Profil | Ortalama şehir içi maliyet/gün | Taksi leg oranı |
|---|---:|---:|
| Balanced | ¥5.273 | %35,0 |
| Cheapest | ¥1.531 | %5,4 |
| Fastest | ¥7.209 | %63,6 |
| Least Walking | ¥6.525 | %59,2 |

---

## 4. Sorunların Katmanlara Ayrılması

Her bulgu motor hatası değildir. Uygulama aşağıdaki ayrımı korumalıdır.

### A. Harness / test verisi sorunları

- Yemek POI çalışma saatleri kaybediliyor.
- Her şehirde tek food POI öğle ve akşam için tekrar kullanılıyor.
- POI havuzu refill edildikten sonra tema parkı tekrar kontrol edilmiyor.
- POI'ler günlere rastgele dağıtılıyor.
- Havuz refill'i gerçek kullanıcı planında tekrar ziyaret üretiyor.
- Sentetik matris koordinattan simetrik süre üretiyor.
- Kahvaltı otelle aynı koordinatta olsa da 3 dakikalık leg oluşuyor.
- `kidFriendly` ve `nightlife` metadata'sı senaryo üretiminde kullanılmıyor.

### B. Optimizer çekirdeği sorunları

- `OptimizationActivity.priority` düşürme politikasında kullanılmıyor.
- Düşürmeden önce başka güne taşıma denenmiyor; motor yalnızca gün içi.
- `hasLuggage` tercihi skora veya hard constraint'e etki etmiyor.
- `waitingMinutes`, transit bekleme ve schedule idle'ı karıştırıyor.
- `routeEfficiency` profile bağlı score'dan üretildiği için profiller arası
  karşılaştırılabilir değil.
- Büyük gruplarda taksi kapasitesi hesaba katılmıyor.

### C. JSON / gözlemlenebilirlik sorunları

- Baseline metrikleri yok.
- Beam sonrası ve local-improvement sonrası ayrı metrik yok.
- `evaluatedStateCount`, `prunedStateCount`, `backtrackingMinutes` ve
  `beamWidth` serialize edilmiyor.
- Otele dönüş legi metrikte var, timeline'da yok.
- Dropped listesi yalnız ID içeriyor; neden ve öncelik yok.
- Schedule activity ID/location ID içermiyor.
- Strict feasibility ile dropping sonrası feasibility ayrılmıyor.
- Matrisin sentetik/estimated niteliği day-level warning'e yansımıyor.

### D. Ürün entegrasyonu sorunları

- Varış/şehir transferi blokları günün gerçek başlangıç saatini belirlemiyor.
- Transfer ve havaalanı maliyetleri trip grand total'a tutarlı birimle girmiyor.
- Günler arası coğrafi atama/ön izleme henüz yok.
- Gerçek yönlü route gateway bağlı değil.

---

## 5. Hedef Optimizasyon Hattı

Yeni akış iki seviyeli olmalıdır:

```text
Plan + kullanıcı tercihleri
        ↓
Girdi normalizasyonu ve veri doğrulama
        ↓
Özel gün/anchor rezervasyonu
        ↓
Şehir içindeki POI'leri günlere coğrafi + zamansal atama
        ↓
Her gün için yönlü RouteMatrix alma
        ↓
BeamSearchItineraryOptimizer ile gün içi sıra ve mod seçimi
        ↓
Swap / move / 2-opt local improvement
        ↓
Günler arası move/swap iyileştirmesi
        ↓
Hard constraint validator
        ↓
Baseline/delta/uyarılarla yapılandırılmış preview
        ↓ açık kullanıcı onayı
Plan persistence
```

### Sorumluluk sınırı

- `TripActivityAssignmentEngine`: Bir şehirdeki aktiviteleri günlere dağıtır.
- `BeamSearchItineraryOptimizer`: Tek bir günün sıra ve ulaşım modunu çözer.
- `RouteOptimizationValidator`: Çıktının hard constraint'lerini bağımsız
  olarak doğrular.
- `PlanOptimizationController`: Ön izleme, karşılaştırma, onay ve persistence.

Gün içi optimizer'a günler arası sorumluluk yüklenmemelidir.

---

## 6. Uygulama Fazları

## Faz 0 — Baseline'ı Kilitle ve Ölçümü Güvenilir Yap

### Yapılacaklar

1. Mevcut `route_opt_scenarios.json` dosyasını altın çıktı olarak commit etme;
   büyük ve sentetik bir artefakttır. Bunun yerine özet metrikleri küçük bir
   fixture'a yaz.
2. `route_opt_harness` için `schemaVersion`, `seed`, `suiteMode`,
   `matrixVersion`, optimizer config ve git SHA alanlarını envelope'a ekle.
3. Harness çıktısında 100 dönüş gününü `optimizerEvaluated:false` olarak
   işaretle.
4. Summary'yi aşağıdaki kategorilere ayır:
   - `optimizerEvaluatedDays`
   - `strictFeasibleDays`
   - `recoveredByDroppingDays`
   - `infeasibleDays`
   - `departureOnlyDays`
   - `requestedActivityCount`
   - `scheduledActivityCount`
   - `droppedActivityCount`
5. Aynı seed ve config ile iki koşumun semantik JSON hash'inin aynı olduğunu
   test et. `generatedAt` ve elapsed time hash dışında tutulmalı.

### Kabul kriteri

- Aynı seed ile iki koşumun bütün senaryo içerikleri birebir aynı.
- `%100 feasible` tek başına başarı göstergesi olarak yazılmıyor.
- Summary'deki sayılar day-level kayıtların reduce sonucuyla eşit.

---

## Faz 1 — P0 Doğruluk Fixleri

### 1.1 Yemek yeri saatlerini koru

#### Kök neden

`_mealLocation`, food POI'yi yalnızca `TripLocation`'a çeviriyor. Kaynak
`openHour/closeHour` kayboluyor; öğle ve akşam aktivitesi genel pencereyle
yeniden oluşturuluyor.

#### Değişiklik

- `_mealLocation` yalnız lokasyon değil, aşağıdaki yapıdaki bir aday döndürsün:

```dart
class MealVenueCandidate {
  const MealVenueCandidate({
    required this.poi,
    required this.supportedPeriods,
    required this.isSynthetic,
  });

  final PoiSpec poi;
  final Set<MealPeriod> supportedPeriods;
  final bool isSynthetic;
}

enum MealPeriod { breakfast, lunch, dinner }
```

- Aktivitenin effective zamanı şu kesişim olmalı:
  `mealPeriodWindow ∩ venueOpeningWindow ∩ dayWindow`.
- Kesişim aktivite süresinden kısaysa aday kullanılamaz.
- Aynı market öğle için geçerli, akşam için geçersiz olabilir.
- Her şehir test fixture'ında en az:
  - 2 lunch adayı,
  - 2 dinner adayı,
  - 1 otel/yakın çevre fallback adayı bulunmalı.
- Synthetic fallback açıkça `isSynthetic:true` ve gerçekçi saatlerle üretilmeli.
- Yemek “fixed” değilse envelope notu “time-window constrained” olarak
  düzeltilmeli. Gerçek rezervasyon varsa `fixedStartTime` kullanılmalı.

#### Regresyon testleri

- Tsukiji 18:00 akşam yemeği adayı olamaz.
- Nishiki 18:00'de başlayan 75 dakikalık akşam yemeği olamaz.
- Kuromon 18:00'de başlayan akşam yemeği olamaz.
- Uygun restoran yoksa valid synthetic dinner oluşur ve warning üretir.
- Restoran rezervasyonu tam sabit saatte korunur.

### 1.2 Tema parkı refill hatasını düzelt

#### Kök neden

Tema parkı kontrolü `refillIfNeeded` çağrısından önce çalışıyor. Refill ile
gelen tema parkı diğer üç POI ile aynı güne girebiliyor.

#### Değişiklik

1. Full day havuzu önce en az ihtiyaç kadar doldur.
2. Dolu havuzda special/full-day POI ara.
3. Varsa yalnız onu seç ve havuzdan çıkar.
4. Yoksa normal POI sayısı kadar seçim yap.

Yalnız `durationMin >= 300` magic number'ına güvenme. `PoiSpec` içine açık bir
gün şablonu ekle:

```dart
enum PoiDayRole { normal, halfDayAnchor, fullDayExclusive, excursion }
```

- DisneySea, USJ → `fullDayExclusive`
- Miyajima → `excursion`
- Uzak Hakone göl rotası gerektiğinde `halfDayAnchor` veya `excursion`

#### Regresyon testleri

- Pool refill sonrasında USJ hiçbir zaman başka sightseeing POI ile aynı güne
  atanmaz.
- DisneySea günü ayrı lunch/dinner durağı üretmez; park içi meal note'u üretir.
- Full-day POI'nin dropping ile “kurtarılması” başarı sayılmaz.

### 1.3 Co-located legleri sıfırla

- İki lokasyon arası mesafe 50 metrenin altındaysa harness matrisinde
  `doorToDoorMinutes:0`, `walkingMinutes:0`, `waitingMinutes:0` seçeneği üret.
- Otel kahvaltısı mümkünse ayrı koordinatlı lokasyon yerine otelin aynı
  location ID'sini kullansın.
- Domain matrix aynı ID için rota gerektirmiyorsa optimizer zero-leg
  davranışını açıkça desteklesin.

#### Kabul kriteri

- 582 kahvaltının toplam yapay 1.746 dakikalık yürüyüşü sıfırlanır.
- Sıfır leg timeline'da transit kartı olarak gösterilmek zorunda değildir.

### 1.4 Hard validator ekle

Optimizer sonucundan bağımsız saf Dart validator şu kontrolleri yapmalı:

- Aktivite zamanları kronolojik ve çakışmasız.
- Her aktivite açılış/kapanış aralığında.
- Fixed aktivite tam saatinde.
- Her transit leg matrix'te mevcut.
- Otel dönüşü `dayEnd` öncesinde.
- Dropped aktivite schedule içinde yok.
- Aynı activity ID aynı gün/gezide ikinci kez yok; yalnız açık tekrar izni
  verilmiş fixture bundan muaf.
- Meal venue kendi gerçek çalışma saatine uyuyor.
- Timeline metrikleriyle aggregate metrikler eşit.

Validator başarısızsa preview kullanıcıya uygulanamaz ve persistence yapılmaz.

---

## Faz 2 — Günler Arası Atama ve Aktivite Koruma

### 2.1 `TripActivityAssignmentEngine` ekle

Önerilen dosya:

`mobile/lib/domain/trip_activity_assignment.dart`

#### Girdi

- Aynı şehirdeki gün pencereleri ve gün tipleri
- Otel
- Aktivite havuzu
- Açılış/kapanış/süre/öncelik/day role/cluster
- Transfer/varış kaynaklı gerçek kullanılabilir başlangıç saati
- Kullanıcı tempo ve aile tercihleri

#### Deterministik atama sırası

1. Fixed/locked/rezervasyonlu aktiviteleri ait oldukları güne yerleştir.
2. `fullDayExclusive` ve `excursion` günlerini rezerve et.
3. Erken kapanan ve yüksek öncelikli aktiviteleri önce ata.
4. Aynı cluster'daki aktiviteleri aynı gün bucket'ına paketle.
5. Her bucket için süre alt sınırı hesapla:
   aktivite süreleri + minimum geçiş alt sınırı + zorunlu yemek + otel dönüşü.
6. Hard lower bound pencereye sığmıyorsa o atamayı ele.
7. Kalan adaylarda deterministik beam/min-cost assignment kullan.
8. İlk çözümden sonra günler arası move ve swap dene.
9. Her günün iç sırasını mevcut `BeamSearchItineraryOptimizer` ile çöz.
10. Bir gün başarısızsa önce aynı şehirde başka güne taşı; ancak bütün günler
    denenince dropping politikasına geç.

#### Assignment maliyeti

Lexicographic öncelik kullanılmalı:

1. Hard violation sayısı
2. Düşürülen `mustDo` sayısı
3. Toplam düşürülen priority mass
4. Düşürülen aktivite sayısı
5. Günler arası cluster parçalanması
6. Tahmini transit alt sınırı
7. Gün yükü dengesizliği
8. Deterministik tie-break key

Weighted score, must-do aktiviteyi düşük transit uğruna düşürememelidir.

### 2.2 Aktivite önceliğini gerçek kurala dönüştür

Mevcut `priority` alanı belgelenmeli ve kullanılmalı. Tercihen enum eklenmeli:

```dart
enum ActivityPriority { optional, normal, preferred, mustDo }
```

Geriye uyum için eski integer alanı adapter'da enum'a çevrilebilir.

Kurallar:

- `mustDo`, fixed kadar zamansal olarak sabit değildir; fakat otomatik
  düşürülemez. Fizibilitesizse typed failure veya kullanıcı kararı gerekir.
- `preferred`, yalnız bütün must-do ve normal çözümler korunduktan sonra
  dropping adayı olur.
- `optional`, ilk dropping havuzudur.
- Meal koruması kategoriye özel hard-coded bir ayrıcalık olmamalı; öğünün
  kendisi required anchor, seçilen restoran ise değiştirilebilir aday olmalı.

### 2.3 Dropping sonucunu yapılandır

`droppedActivityIds` korunabilir, fakat yeni bir yapı eklenmeli:

```dart
class DroppedActivity {
  final String activityId;
  final String name;
  final ActivityPriority priority;
  final DropReason reason;
  final List<int> attemptedDayIndexes;
  final String? conflictingActivityId;
}

enum DropReason {
  noRoute,
  openingWindowConflict,
  dayCapacity,
  walkingLimit,
  fixedActivityConflict,
  duplicate,
  userOptional,
}
```

### 2.4 Tekrar ziyaret politikasını ayır

- `suiteMode: stress` havuz refill'ine izin verebilir; her tekrar
  `repeatFixture:true` olarak etiketlenir.
- `suiteMode: product` aynı activity ID'yi gezi boyunca ikinci kez seçmez.
- Ürün kalite kabulü yalnız `product` suite'i üzerinden yapılır.

#### Faz 2 kabul kriterleri

- Miyajima taleplerinin en az %90'ı excursion gününe atanır; kalanların nedeni
  yapılandırılmıştır.
- USJ/DisneySea başka POI ile aynı güne karışmaz.
- Product suite'te açıklanmamış duplicate POI sayısı sıfırdır.
- Gün içi doğrudan dropping öncesinde aynı şehirdeki tüm uygun günler denenir.
- Full-day dropping oranı `%41` baseline'ından `%10` altına iner.
- Toplam gezi POI dropping oranı `%11,3` baseline'ından `%3` altına iner.

---

## Faz 3 — Geri Dönüş ve Bekleme İyileştirmesi

### 3.1 Meal venue'yu rota ile birlikte seç

Meal venue gün atamasından önce tek bir noktaya sabitlenmemeli. Optimizer'a
aynı öğün anchor'ı için alternatif lokasyonlar sunulmalı.

Önerilen yaklaşım:

- `MealAnchor` zorunlu zaman/süre ihtiyacını temsil eder.
- `MealVenueCandidate[]` gerçek lokasyon alternatifleridir.
- Beam genişlemesinde anchor'a gelindiğinde hem sıra hem venue adayı seçilir.
- Aynı öğün için yalnız bir venue schedule'a girer.
- Dinner adayının maliyetine:
  - son sightseeing cluster'ından erişim,
  - dinner→otel dönüşü,
  - yeniden cluster giriş cezası birlikte dahil edilir.

### 3.2 Waiting alanlarını ayır

Yeni metrikler:

```text
rideMinutes
walkingMinutes
accessMinutes
transitWaitMinutes
scheduleIdleMinutes
bufferMinutes
doorToDoorMinutes
```

Kurallar:

- `doorToDoorMinutes`, bileşenlerin toplamıdır.
- `scheduleIdleMinutes`, leg içine gizlenmez; timeline'da `kind: idle` olur.
- UI toplam süre hesaplarken waiting'i door-to-door üzerine yeniden eklemez.
- 30 dakikadan uzun idle için açıklama veya açık serbest zaman bloğu üretilir.

### 3.3 Cluster re-entry'yi sertleştir

- Aynı cluster'a ikinci giriş, fixed/meal zorunluluğu yoksa güçlü ceza almalı.
- Venue alternatifleri varken re-entry üreten venue elenmeli veya ağır
  cezalandırılmalı.
- Günler arası atama cluster'ı iki güne bölüyorsa, günlük optimizer bunu tek
  başına düzeltemeyeceğinden cross-day local improvement çalışmalı.

#### Faz 3 kabul kriterleri

- Re-entry içeren gün oranı `%62,7` → `%25` altı.
- Kyoto re-entry oranı `%94,1` → `%30` altı.
- `scheduleIdleMinutes > 90` olan gün oranı `%5` altı.
- Hiçbir `idle` transit wait olarak raporlanmaz.
- Dinner→hotel return leg her gün timeline'da görünür.

---

## Faz 4 — Maliyet, Profil ve Skor Modeli

### 4.1 Maliyet birimini düzelt

Her leg şu alanları taşımalı:

```text
costPerPersonYen
partyTotalCostYen
vehicleCount
fareBasis: perPerson | perVehicle | flat
```

Taksi için:

```text
vehicleCount = ceil(partySize / taxiCapacity)
partyTotal = vehicleFare * vehicleCount
perPerson = partyTotal / partySize
```

Başlangıç varsayımı `taxiCapacity = 4`; provider kapasite veriyorsa o kullanılır.
Toplu taşımada `partyTotal = perPersonFare * farePayingPassengerCount`.
Çocuk tarifesi henüz modellenmiyorsa açık warning/assumption yazılmalı.

Trip toplamları:

- `inCityCostPerPersonYen`
- `inCityPartyTotalYen`
- `interCityCostPerPersonYen`
- `interCityPartyTotalYen`
- `airportCostPerPersonYen`
- `airportPartyTotalYen`
- `grandTotalPerPersonYen`
- `grandTotalPartyYen`

### 4.2 Profile-independent efficiency kullan

Mevcut `routeEfficiencyScore`, profile bağlı score ile travel farkından
hesaplandığı için Cheapest profilde 100 üretip diğer profillerle anlamsız
karşılaştırma yapabiliyor.

Yeni yaklaşım:

- Ham profile score yalnız `objectiveScore` adıyla ve profil etiketiyle verilir.
- Asıl iyileştirme, aynı girdi ve aynı profil için baseline'a göre hesaplanır:
  - `travelDeltaMinutes`
  - `walkingDeltaMinutes`
  - `idleDeltaMinutes`
  - `transferDelta`
  - `partyCostDeltaYen`
  - `backtrackingDelta`
  - `objectiveScoreDelta`
  - `objectiveImprovementPct`
- Profil bağımsız tek bir “efficiency” puanı zorunlu değildir. UI ham delta
  gösterebilir; yanlış birleşik puandan daha güvenlidir.

### 4.3 Aynı girdiyi dört profille çalıştır

Scenario generator önce profilesiz `BaseScenarioSpec` üretmeli. Ardından her
base scenario Balanced/Fastest/LeastWalking/Cheapest ile çalıştırılmalı.

Kontrollü kabul kontrolleri:

- Fastest, paired suite ortalamasında en düşük travel süresini üretir.
- Least Walking, paired suite ortalamasında en düşük walking süresini üretir.
- Cheapest, paired suite ortalamasında en düşük party total maliyeti üretir.
- Bütün profiller aynı hard constraint setini geçer.
- Profil değişimi must-do aktivite kaybına neden olmaz.

### 4.4 Beam width tutarsızlığını kapat

Dokümanlarda varsayılan beam width `6`, kodda `7` görünüyor.

- Önce kaynak doğruluğu gereği kod varsayılanını `6` ile hizala.
- Ardından aynı paired suite'i `6`, `7` ve `10` ile benchmark et.
- Kalite kazanımı anlamlı değilse düşük maliyetli değer `6` kalmalı.
- Seçilen değer kod, docs ve JSON envelope'ta aynı olmalı.

#### Faz 4 kabul kriterleri

- Hiçbir cost alanı birim etiketsiz değildir.
- 5–6 kişilik grupta tek taksi varsayılmaz.
- Profile score profiller arası kalite puanı olarak kullanılmaz.
- Dört profil aynı base senaryolarda paired olarak raporlanır.
- Docs/kod/JSON beam width değeri tutarlıdır.

---

## Faz 5 — Transfer, Bagaj ve Matris Gerçekçiliği

### 5.1 Transfer bloklarını timeline'a bağla

Arrival/city transfer yalnız açıklama bloğu olmamalı.

- Flight arrival veya şehir transfer başlangıç/bitiş saatleri fixed transit
  segment olarak timeline'a girer.
- Sightseeing `availableStartTime` şu şekilde hesaplanır:

```text
max(userDayStart, transferArrival + stationExit + hotelDrop/checkInBuffer)
```

- Transfer maliyetleri grand total'a aynı kişi/party birimleriyle eklenir.
- Departure transferi de route summary ve grand total'a girer.

### 5.2 Bagaj tercihini işler hale getir

`hasLuggage` tek boolean yerine mümkünse:

```dart
enum LuggageState { none, carried, checkedAtHotel, forwarded }
```

- `carried`: yürüme limiti düşer, çok aktarma ve merdivenli istasyon cezası
  yükselir, gerekirse taksiye pozitif tercih verilir.
- `checkedAtHotel`: şehir içi gezi normal profile döner.
- `forwarded`: transfer karmaşıklığı cezası azalabilir.

### 5.3 Harness matrisini gerçekten yönlü yap

Sentetik test matrisinde en az şu varyasyonlar bulunmalı:

- A→B ve B→A için farklı station ingress/egress süresi.
- Sabah/öğlen/akşam time slice.
- Tek yönlü bus veya yön bağımlı transfer sayısı fixture'ı.
- Büyük istasyon için açık complexity/transfer buffer metadata'sı.
- Düşük reliability ve alternate provider senaryosu.
- Bütün sentetik seçenekler `isEstimated:true` olarak işaretlenmeli.

Gerçek provider geldiğinde sentetik değerler üretim fallback'i olarak sessizce
kullanılmamalıdır; typed estimated/unavailable politikası korunmalıdır.

#### Faz 5 kabul kriterleri

- Transfer süresi gezi penceresiyle çakışmıyor.
- Bagajlı transfer profili bagajsız profille birebir aynı sonuç vermiyor;
  beklenen ceza/mode farkı testte gözleniyor.
- A→B/B→A asimetrisi en az bir sabit regresyon senaryosunda doğrulanıyor.
- Sentetik rota warning'siz “gerçek rota” gibi görünmüyor.

---

## 7. Hedef JSON Şeması

Mevcut alanlar geriye uyum için korunabilir; yeni alanlar `schemaVersion:2`
altında eklenmelidir.

```json
{
  "schemaVersion": 2,
  "generatedAt": "2026-08-03T00:00:00.000",
  "suite": {
    "seed": 20260803,
    "mode": "product",
    "scenarioCount": 100,
    "matrixVersion": "harness-directional-v2",
    "matrixEstimated": true
  },
  "optimizerConfig": {
    "name": "BeamSearchItineraryOptimizer",
    "beamWidth": 6,
    "localImprovementPasses": 3,
    "allowActivityDropping": true
  },
  "summary": {
    "totalDayRecords": 0,
    "optimizerEvaluatedDays": 0,
    "strictFeasibleDays": 0,
    "recoveredByDroppingDays": 0,
    "infeasibleDays": 0,
    "departureOnlyDays": 0,
    "requestedActivities": 0,
    "scheduledActivities": 0,
    "droppedActivities": 0,
    "duplicateActivities": 0,
    "hardViolationCount": 0
  },
  "scenarios": [
    {
      "id": 1,
      "profile": "balanced",
      "days": [
        {
          "dayIndex": 1,
          "optimizerEvaluated": true,
          "strictFeasible": false,
          "recoveredByDropping": true,
          "inputActivities": [
            {
              "id": "poi-id",
              "name": "POI",
              "priority": "normal",
              "clusterId": "central",
              "dayRole": "normal"
            }
          ],
          "timeline": [
            {
              "kind": "activity",
              "activityId": "poi-id",
              "locationId": "loc-id",
              "start": "09:00",
              "end": "10:00"
            },
            {
              "kind": "transit",
              "fromLocationId": "loc-a",
              "toLocationId": "loc-b",
              "mode": "metro",
              "start": "10:00",
              "end": "10:24",
              "doorToDoorMinutes": 24,
              "walkingMinutes": 7,
              "transitWaitMinutes": 4,
              "bufferMinutes": 10,
              "costPerPersonYen": 220,
              "partyTotalCostYen": 660,
              "isEstimated": true
            },
            {
              "kind": "idle",
              "start": "10:24",
              "end": "10:40",
              "minutes": 16,
              "reason": "venue_opening"
            },
            {
              "kind": "return",
              "fromLocationId": "last-poi",
              "toLocationId": "hotel-id",
              "start": "20:00",
              "end": "20:25"
            }
          ],
          "dropped": [
            {
              "activityId": "optional-id",
              "name": "Optional POI",
              "priority": "optional",
              "reason": "day_capacity",
              "attemptedDayIndexes": [2, 3]
            }
          ],
          "stages": {
            "baseline": {
              "objectiveScore": 0,
              "travelMinutes": 0,
              "walkingMinutes": 0,
              "scheduleIdleMinutes": 0,
              "backtrackingMinutes": 0
            },
            "beam": {
              "objectiveScore": 0,
              "evaluatedStateCount": 0,
              "prunedStateCount": 0
            },
            "localImprovement": {
              "objectiveScore": 0,
              "passesApplied": 0,
              "acceptedMoves": []
            }
          },
          "metrics": {
            "doorToDoorMinutes": 0,
            "walkingMinutes": 0,
            "transitWaitMinutes": 0,
            "scheduleIdleMinutes": 0,
            "transferCount": 0,
            "clusterReentryCount": 0,
            "costPerPersonYen": 0,
            "partyTotalCostYen": 0,
            "objectiveScore": 0
          },
          "delta": {
            "travelMinutes": 0,
            "walkingMinutes": 0,
            "scheduleIdleMinutes": 0,
            "transferCount": 0,
            "partyCostYen": 0,
            "backtrackingMinutes": 0,
            "objectiveScore": 0,
            "objectiveImprovementPct": 0
          },
          "warnings": []
        }
      ]
    }
  ]
}
```

### Şema kuralları

- `objectiveScore` yalnız aynı profile ve aynı girdiye ait sonuçlarla
  karşılaştırılır.
- Bütün süreler dakika, bütün para alanları `Yen` suffix'i taşır.
- `timeline` aggregate edildiğinde `metrics` ile eşleşir.
- `return` legi zorunludur; başlangıç ve bitiş aynı lokasyonsa zero-leg olabilir.
- `warnings`, sentetik/estimated matris kullanımını açıkça söyler.
- Human-readable `optimizationChanges` korunabilir, fakat source of truth
  structured `acceptedMoves` ve `delta` alanlarıdır.

---

## 8. Dosya Bazlı Değişiklik Haritası

| Dosya / yeni dosya | Değişiklik |
|---|---|
| `mobile/tool/route_opt_harness/main.dart` | Schema v2 envelope, strict summary, seed/config/matrix metadata |
| `mobile/tool/route_opt_harness/planner.dart` | Meal adayları, transfer entegrasyonu, structured timeline/metrics |
| `mobile/tool/route_opt_harness/scenario.dart` | Profilesiz base scenario + dört profil expansion, suite mode |
| `mobile/tool/route_opt_harness/poi_data.dart` | Meal period, day role, gerçek saatler, yeterli restoran fixture'ı |
| `mobile/tool/route_opt_harness/matrix_builder.dart` | Zero leg, direction/time slice, estimated flag, maliyet bileşenleri |
| `mobile/lib/domain/itinerary_optimizer.dart` | Priority-aware dropping, waiting split, structured stage metrics |
| `mobile/lib/domain/route_matrix.dart` | Cost basis, vehicle count, time components, luggage metadata |
| `mobile/lib/domain/trip_activity_assignment.dart` | Yeni şehir içi günler arası atama motoru |
| `mobile/lib/domain/route_optimization_validator.dart` | Yeni bağımsız hard validator |
| `mobile/lib/features/plans/plan_optimization_controller.dart` | Cross-day preview, strict/recovered durumları, delta adapter |
| `mobile/test/domain/itinerary_optimizer_test.dart` | Priority/drop/wait/cost/profile regresyonları |
| `mobile/test/domain/trip_activity_assignment_test.dart` | Yeni assignment/special-day/cross-day testleri |
| `mobile/test/domain/route_optimization_validator_test.dart` | Hard constraint testleri |
| `mobile/test/tool/route_opt_harness_test.dart` | Summary, determinism, JSON schema ve kalite eşikleri |
| `docs/ROUTE_OPTIMIZATION.md` | Yeni iki seviyeli mimari ve metrikler |
| `docs/ARCHITECTURE.md` | Yeni domain servisleri ve veri akışı |
| `docs/DECISIONS.md` | Cross-day assignment, priority/drop ve cost-unit kararı |
| `docs/CURRENT_TASK.md` | Faz ilerleme ve doğrulama sonuçları |

Dosya adları mevcut ağaçla uyuşmuyorsa aynı sorumluluk sınırı korunarak yakın
eşdeğer seçilebilir; yeni sorumluluklar UI widget'larına gömülmemelidir.

---

## 9. Test Matrisi

## 9.1 Saf domain unit testleri

### Zaman ve hard constraint

- Erken kapanan POI kapanıştan sonra planlanamaz.
- Fixed reservation tam saatinde kalır.
- Gün sonu otel dönüşü sığmıyorsa rota başarısızdır.
- Meal venue ve meal period saatlerinin kesişimi doğrulanır.
- Timeline overlap ve aggregate metric mismatch validator tarafından yakalanır.

### Assignment

- USJ/DisneySea exclusive day.
- Miyajima excursion day.
- Horyu-ji uzak cluster, yakın cluster gününü bölmez.
- Erken kapanan Tenryu-ji uygun sabah/öğlen bucket'ına gider.
- Bir gün doluysa başka uygun güne taşınır.
- Must-do bütün günler denendikten sonra typed failure verir; düşmez.
- Optional aktivite gerekçeli biçimde düşebilir.

### Maliyet/profil

- 1–4 kişi bir taksi, 5–8 kişi iki taksi.
- Public transit party total doğru çarpılır.
- Cheapest paired scenario'da en düşük party total.
- Fastest paired scenario'da en düşük travel.
- Least Walking paired scenario'da en düşük walking.

### Matris

- A→B süresi B→A yerine kullanılamaz.
- Zero-distance leg sıfırdır.
- Estimated leg warning üretir.
- Bagajlı route scoring daha az yürüme/aktarma tercih eder.

## 9.2 Sabit adversarial fixture'lar

- **R1 — Tokyo market saatleri:** Tsukiji lunch olabilir, dinner olamaz.
- **R2 — Kyoto dinner dönüşü:** Nishiki kapanış sonrası dinner olamaz; son
  Higashiyama POI'sine yakın açık restoran seçilir.
- **R3 — Osaka refill:** Boşalan pool refill edilince USJ tek güne ayrılır.
- **R4 — Hiroshima excursion:** Miyajima aynı gün center POI'lerle zorla
  paketlenmez.
- **R5 — Nara uzak cluster:** Horyu-ji ayrı half-day bucket'a atanır.
- **R6 — Family:** Çocuklu grupta günlük walking cap aşılmaz.
- **R7 — Large party:** 6 kişilik taksi iki araç olarak maliyetlenir.
- **R8 — Luggage transfer:** Bagajlı gün çok aktarmalı/yürümeli rotadan kaçınır.
- **R9 — Fixed dinner:** 19:00 rezervasyonu sabit, çevresi yeniden sıralanır.
- **R10 — Impossible must-do:** Sessiz dropping yerine typed failure.
- **R11 — Directionality:** A→B/B→A farklı süre ve mod seçimi.
- **R12 — Idle:** 150 dakikalık boşluk transit waiting olarak raporlanmaz.

## 9.3 100 senaryoluk kalite kapısı

Aynı seed `20260803`, product mode ve dört paired profile ile çalıştırılır.

Zorunlu eşikler:

| Kontrol | Kabul |
|---|---:|
| Hard constraint violation | 0 |
| Geçersiz saatli meal venue | 0 |
| Açıklanmamış duplicate POI | 0 |
| Full-day POI'nin başka POI ile karışması | 0 |
| Must-do dropping | 0 |
| Toplam POI dropping oranı | <%3 |
| Full-day dropping oranı | <%10 |
| Cluster re-entry'li gün | <%25 |
| Kyoto cluster re-entry'li gün | <%30 |
| Schedule idle >90 dk | <%5 |
| Return leg eksik gün | 0 |
| Birimsiz maliyet alanı | 0 |
| Estimated matrix warning eksikliği | 0 |
| Semantic determinism farkı | 0 |

Performans kapısı:

- Mevcut ürün hedefi korunur: 13 günlük plan üretimi ≤300 ms uygun cihaz/test
  ortamında.
- Harness 100 base senaryo × 4 profil çalıştıracağı için ayrı bütçe tutulur;
  CI makinesinde baseline kaydedilir ve %20'den büyük sebepsiz regresyon fail
  olur.
- JSON boyutu stage trace nedeniyle büyürse `--trace=summary|full` seçeneği
  eklenir; varsayılan `summary` olur.

---

## 10. Uygulama Sırası ve Önerilen Commitler

Her commit tek sorumluluk taşımalıdır:

1. `test(route): lock strict baseline and schema-v2 summary`
2. `fix(route-harness): preserve meal venue hours and meal periods`
3. `fix(route-harness): isolate full-day POIs after pool refill`
4. `fix(route-matrix): support zero-distance legs and explicit estimates`
5. `feat(route): add independent hard-result validator`
6. `feat(route): assign city activities across days before day routing`
7. `feat(route): make dropping priority-aware and structured`
8. `feat(route): split transit wait, idle and buffer metrics`
9. `feat(route): select meal venues inside route optimization`
10. `fix(route-cost): separate per-person and party-total cost`
11. `test(route): run every base scenario against four profiles`
12. `feat(route): integrate transfers and luggage state`
13. `test(route): add directional matrix and adversarial fixtures`
14. `docs(route): document two-level optimizer and final benchmarks`

Her committen sonra hedefli test; Faz 1, Faz 2, Faz 4 ve finalde tam
`flutter analyze` + `flutter test` çalıştırılmalıdır.

---

## 11. Definition of Done

Çalışma ancak aşağıdaki maddelerin tamamı sağlandığında bitmiş sayılır:

- [ ] Faz 0–5 tamamlandı.
- [ ] P0/P1 issue'lar için ayrı regresyon testi var.
- [ ] 12 adversarial fixture yeşil.
- [ ] 100 senaryo × 4 paired profile kalite kapısı yeşil.
- [ ] Hard constraint violation sıfır.
- [ ] Must-do veya fixed aktivite sessizce düşmüyor.
- [ ] Yemek yeri gerçek çalışma saatine uyuyor.
- [ ] Full-day/excursion POI doğru güne ayrılıyor.
- [ ] Günler arası taşıma dropping'den önce deneniyor.
- [ ] Re-entry, idle ve dropping eşikleri sağlanıyor.
- [ ] Return leg ve bütün metric bileşenleri JSON'da denetlenebilir.
- [ ] Maliyet kişi başı ve grup toplamı olarak tutarlı.
- [ ] Profile karşılaştırmaları paired girdilerde yapılıyor.
- [ ] Kod/doküman/JSON beam width tutarlı.
- [ ] Sentetik rota estimated olarak işaretli.
- [ ] `flutter analyze` 0 error.
- [ ] Yeni ve ilgili mevcut testler yeşil.
- [ ] Tam test paketindeki önceden var olan hatalar baseline ile ayrıştırıldı.
- [ ] `docs/ROUTE_OPTIMIZATION.md`, `ARCHITECTURE.md`, `DECISIONS.md` ve
      `CURRENT_TASK.md` güncellendi.
- [ ] Gizli anahtar veya hassas kullanıcı verisi log/JSON/diff içine girmedi.

---

## 12. Uygulayıcıya Verilecek Kısa Talimat

Aşağıdaki metin yeni bir uygulama görevinde bu belgeyle birlikte verilebilir:

```text
docs/ROUTE_OPTIMIZATION_FIX_PLAN.md belgesini kaynak plan kabul ederek Faz 0'dan
Faz 5'e sırayla uygula. Her fazda önce ilgili regresyon testlerini ekle, sonra
kodu değiştir. Harness kaynaklı sorunları optimizer çekirdeğine taşımadan çöz;
çekirdek değişikliklerini saf Dart tut. Üretim akışında aktiviteyi sessizce
düşürme ve AI'a rota kararı verme. Her faz sonunda hedefli testleri, ana
kilometre taşlarında flutter analyze ve tam flutter test paketini çalıştır.
Mevcut dirty worktree'deki kullanıcı değişikliklerini koru. Kalite kapısındaki
eşikler sağlanmadan görevi tamamlandı sayma; sonuçta eski/yeni ölçümleri tablo
olarak raporla ve gerekli mimari belgeleri güncelle.
```

---

## 13. Beklenen Sonuç

Bu plan uygulandığında rota motoru:

- kapalı mekana ziyaret veya yemek yazmayacak,
- özel/uzak noktaları doğru gün tipine ayıracak,
- aktivite silmeden önce aynı şehirde başka güne taşıyacak,
- kullanıcı önceliğini dropping kararının önüne koyacak,
- cluster geri dönüşlerini ve uzun boşlukları belirgin biçimde azaltacak,
- maliyeti kişi/grup/araç bazında doğru hesaplayacak,
- aynı senaryoda dört profil arasındaki farkı güvenilir biçimde gösterecek,
- baseline, beam search ve local improvement kazancını ayrı ayrı ölçecek,
- sentetik ve gerçek rota verisini kullanıcıdan ve testlerden gizlemeyecek,
- her sonucu bağımsız hard validator ile persistence öncesinde doğrulayacaktır.

