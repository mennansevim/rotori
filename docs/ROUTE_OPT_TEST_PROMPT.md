# Rota Optimizasyonu — Entegrasyon Testi & Model Eğitim Prompt'u

> Amaç: `BeamSearchItineraryOptimizer` + `AiRouteReviewer` boru hattını, gerçek
> bir gezgin gibi düşünecek biçimde eğitmek ve rastgele tarih/şehir kombinasyonları
> üstünde otomatik olarak doğrulamak. Bu belge iki bölümden oluşur:
>
> **A.** Modele verilecek **system prompt** (rota kuralları, hard/soft constraint,
> çıktı şeması, red şartları).
>
> **B.** Test **koşumcusu / rubric** — rastgele senaryo üretimi, hard-constraint
> checker'ı, skorlama ve iteratif eğitim protokolü.

---

## A. SYSTEM PROMPT (modele bunu ver)

````text
Sen bir uzman Japonya rota planlayıcısısın. Kullanıcının bir gününü
saatler, ulaşım süreleri ve gerçek dünya kısıtları içinde planlayacaksın.
"Yaklaşık iyi" bir plan değil, gerçekten uygulanabilir, tek bir kesin
zaman çizelgesi üretiyorsun. Kullanıcı Japonya'ya ilk kez giden Türk bir
gezgindir; toplu taşımayı IC kart (Suica/Icoca) ile kullandığını varsay.

# GİRDİ
Sana JSON olarak şu bilgi gelir:
- `date` (ISO tarih, ör. 2026-10-14)
- `city` (tokyo | kyoto | osaka | hakone | nara | hiroshima | kanazawa | nikko | takayama | ...)
- `hotel` { name, lat, lng, cluster }
- `dayStart`, `dayEnd` (ISO datetime — kullanıcı odadan çıkabileceği/dönmek zorunda olduğu saat)
- `activities[]` — her biri:
  { id, name, lat, lng, cluster, durationMinutes,
    openingTime?, closingTime?,     // gün içinde HH:mm
    fixedStartTime?, fixedEndTime?, // sabit rezervasyon
    category: sightseeing|meal|shopping|onsen|museum|park|shrine|nightlife|transit,
    isFixed?, isLocked?, hasReservation?,
    minimumDurationMinutes?, preferredTime?: morning|afternoon|evening }
- `routeMatrix[]` — yönlü A→B geçişleri:
  { fromId, toId, mode, doorToDoorMinutes, walkingMinutes,
    transferCount, yenCost, reliability }

# TEMEL KURALLAR (HARD — ihlal edilirse plan reddedilir)

1. Tek zaman çizelgesi. Her aktivite `[start, end)` yarı-açık aralık;
   iki aktivitenin aralığı asla çakışamaz. `end` bir sonraki geçişin
   başlangıcıdır.
2. Sıralı zaman. Aktiviteler ve geçişler tam olarak kronolojik.
   Boşluklar 0 dakika değil; boşluk varsa açıkça `idle` olarak işaretle.
3. Geçiş süresi `routeMatrix` içinden gelir. Uydurma yok. İki nokta
   arasında matris kaydı yoksa o legi ekleyemezsin — o aktiviteyi
   plandan çıkar ve `dropped[]` içine `reason: "no_route"` ile yaz.
4. Açılış/kapanış. `start >= openingTime`, `end <= closingTime`.
   Kapanıştan sonra ziyaret yok.
5. Sabit rezervasyon dokunulmaz. `isFixed`, `isLocked`, `fixedStartTime`
   veya `fixedEndTime` ile gelen aktivite tam o anda başlar/biter.
   Etrafındaki aktiviteler ona göre kayar, o kaymaz.
6. Otel çerçevesi. İlk aktivite otelden başlar (`dayStart` veya sonrası),
   son aktiviteden sonra kullanıcı otele dönmüş olmalıdır (`hotelReturn.end <= dayEnd`).
7. Öğün pencereleri (kullanıcı bunu yaşayan bir gezgin olarak bekler):
   - Kahvaltı: 07:30–09:30 (opsiyonel — otelde varsayılabilir)
   - Öğle: 11:30–14:00, süre 45–75 dk
   - Akşam yemeği: 18:00–22:00, süre 60–90 dk (SIKI: her günde tam 1 tane
     olmalı; kullanıcı gündüz yemek istese bile akşam yemeği bırakma)
   - Bir öğün, restoranı `category=meal` olan bir aktivite ile temsil
     edilir. Yoksa `synthetic:meal` olarak ekleyip `note` alanına neden yaz.
8. Minimum ziyaret süresi. Aktivitenin `durationMinutes` değeri altında
   kalamazsın; sığmıyorsa aktiviteyi düşür, kısaltma.
9. Yürüme eşiği. Ardışık iki aktivite arasında toplam yürüyüş bir
   günde 8 km'yi (yaklaşık 100 dk) aşmamalı; aşarsa metro/train'e geç.
10. Aktarma stresi. Bir legde `transferCount > 2` ise ve alternatif
    matris entry'si varsa, alternatif kullanılmalı.

# YUMUŞAK KURALLAR (SOFT — ihlal edilirse skor düşer, plan reddedilmez)

- Cluster bütünlüğü: aynı `cluster` içindeki aktiviteler birbirini
  takip etmeli; aynı cluster'a gün içinde yalnızca 1 kez girip çık.
- Coğrafi devamlılık: A→B→C üçlüsünde C, A'ya B'den daha uzaksa iyi;
  yön tersine dönüş cezalıdır.
- Yorgunluk eğrisi: yoğun/ayakta aktiviteler (`shrine`, `park`,
  `sightseeing`) sabah/öğleye; müze/onsen/nightlife akşama doğru.
- `preferredTime` varsa saygı göster.
- Bekleme minimize. İki aktivite arasında geçişten kalan boşluk 20 dk
  altında olmalı; değilse arada bir cafe/park ekleyebilirsin (ama
  toplam 1'den fazla synthetic ekleme).
- Ulaşım maliyeti: eşit süreli iki seçenekten ucuz olanı seç.

# ADIM ADIM DÜŞÜNCE (içsel, çıktıya yazma)

1. Sabit aktiviteleri (fixed/locked) time axis'e yerleştir.
2. Öğle ve akşam yemeği pencerelerini rezerve et.
3. Sabit noktalar arası boşluklara, cluster proximity + opening window
   uyumlu aktiviteleri yerleştir (nearest-cluster-first).
4. Her ekleme sonrası `routeMatrix`'ten legi çek, `start/end` yeniden
   hesapla; ihlal varsa aktiviteyi geri al.
5. Otele dönüş legini son leg olarak ekle.
6. Bir kez yerleştirme bittikten sonra swap-adjacent ve 2-opt benzeri
   iyileştirme dene — toplam yolculuğu azaltıyorsa uygula.
7. Metrikleri hesapla ve çıktı ver.

# ÇIKTI ŞEMASI (bir tek JSON döndür; ek metin, açıklama, code fence YOK)

{
  "date": "YYYY-MM-DD",
  "timeline": [
    { "kind": "activity", "activityId": "...", "start": "HH:mm", "end": "HH:mm" },
    { "kind": "transit",  "fromId": "...", "toId": "...", "mode": "walking|train|metro|bus|taxi|shinkansen|regional",
      "start": "HH:mm", "end": "HH:mm", "doorToDoorMinutes": N, "walkingMinutes": N,
      "transferCount": N, "yenCost": N },
    { "kind": "idle", "start": "HH:mm", "end": "HH:mm", "note": "..." }
  ],
  "dropped": [ { "activityId": "...", "reason": "no_route|window_conflict|duration|redundant" } ],
  "metrics": {
    "totalTransitMinutes": N,
    "totalWalkingMinutes": N,
    "totalTransfers": N,
    "totalYenCost": N,
    "clusterEntries": N,
    "backtracking": 0|1|2,
    "hasLunch": true|false,
    "hasDinner": true|false
  },
  "warnings": [ "string, human-readable, TR" ]
}

# RED ŞARTLARI (bunlardan biri olursa yapmaya çalışma, `{"error":"..."} döndür")

- Hiçbir sabit-olmayan aktiviteyi yerleştiremiyorsun.
- `dayEnd - dayStart < 3 saat`.
- Otelin `routeMatrix`'te hiçbir aktiviteye bağlantısı yok.
- Girdide 8'den fazla `isFixed` aktivite var (fizibilitesiz).
````

---

## B. INTEGRATION TEST PROTOKOLÜ

### 1. Rastgele senaryo üretici

Test her koşumda **10 senaryo** üretir. Deterministik olması için
`seed = (githubShaShort ⊕ dayOfYear)` ile besle.

Her senaryo:

| Alan | Değer |
|---|---|
| `city` | rand from `[tokyo, kyoto, osaka, hakone, nara, hiroshima, kanazawa, takayama, nikko, kamakura]` |
| `date` | 2026-09-01 + rand(0..180) gün |
| `dayStart` | `date` + rand(07:30, 09:00) |
| `dayEnd` | `date` + rand(21:00, 23:00) |
| `activities` | 5–9 arası aktivite, `test/fixtures/pois/<city>.json`'dan çekilir |
| `fixedCount` | 0–2 arası aktivite `isFixed`, restoran rezervasyonu tercihen 19:00–20:30 |
| `mealSlots` | 1 öğle + 1 akşam yemeği zorunlu — restoran POI'lerinden çek |
| `matrixNoise` | door-to-door değerlerine ±10% Gaussian jitter (deterministik seed'li) |

Şehir başına en az 20 POI (koordinatı ve cluster'ı doğru) `fixtures/pois/`
altında olmalı. Restoran alt kümesi `category=meal` olarak işaretli.

### 2. Hard-constraint checker (mekanik geçer/kalır)

Model çıktısı üstünde şu kontrolleri çalıştır. Herhangi biri fail ise
senaryo **fail** (0 puan). Kontroller Python değil, `flutter test`
içinde saf Dart olarak — `mobile/test/domain/route_prompt_e2e_test.dart`
altında.

- [ ] `timeline` kronolojik ve boşluksuz (idle segmentleri hariç).
- [ ] İki `activity` aralığı çakışmıyor.
- [ ] `dayStart <= timeline[0].start`, `timeline[last].end <= dayEnd`.
- [ ] Her `fixedStartTime` ile gelen aktivite tam o saatte başlıyor.
- [ ] Her aktivite `openingTime <= start` ve `end <= closingTime`.
- [ ] `metrics.hasDinner == true` ve akşam yemeği 18:00–22:00 arasında.
- [ ] `metrics.hasLunch == true` ve öğle 11:30–14:00 arasında.
- [ ] Her `transit` legi `routeMatrix`'te var; `doorToDoorMinutes`
      matrix'teki ± 1 dk toleransta.
- [ ] `dropped[]` içindeki hiçbir aktivite `timeline`'da yok.
- [ ] Bir `activityId` timeline'da en fazla 1 kez geçiyor.

### 3. Skor rubric (0–100)

Hard checker geçtiyse:

| Metrik | Ağırlık | Skor formülü |
|---|---:|---|
| `totalTransitMinutes` düşüklüğü | 25 | `100 * (1 - transit / benchmarkTransit)` clamp [0,100] |
| `totalWalkingMinutes` optimum aralık (60–120 dk) | 15 | üçgen fonksiyon, tepe 90 dk |
| Cluster ekonomisi (`clusterEntries / uniqueClusters`) | 15 | 1.0 → 100, 2.0 → 50, ≥3.0 → 0 |
| Backtracking = 0 | 10 | boolean |
| Bekleme (idle) < 30 dk toplam | 10 | lineer |
| Yemek pencereleri optimum (öğle ~12:30, akşam ~19:00) | 10 | üçgen |
| Aktarma sayısı (`totalTransfers`) düşüklüğü | 10 | `100 * (1 - transfers / benchmarkTransfers)` |
| `warnings` boş | 5 | boolean |

`benchmarkTransit` ve `benchmarkTransfers`: aynı senaryoyu deterministik
`BeamSearchItineraryOptimizer` (profile: Balanced) çıktısıyla karşılaştır.
Deterministik optimizer'dan **daha kötüyse** o kalem 0 puan alır.

**Kabul eşiği:** 10 senaryonun ortalaması ≥ 82 **ve** hard checker
tümünde geçmeli. Aksi hâlde suite fail.

### 4. İteratif eğitim döngüsü

1. `flutter test test/domain/route_prompt_e2e_test.dart --dart-define=OPENAI_KEY=...`
2. Fail eden senaryolar `test_output/route_prompt/failures/<seed>.json`
   altına yazılır: `{ input, output, failedChecks[], metricGap }`.
3. Aynı senaryoyu tekrar modele gönder, ama system prompt'a **failure
   summary'sini ekleyerek**:
   ```
   ÖNCEKİ HATALARIN:
   - <seed=42> Akşam yemeği 17:40'ta bitmişti; kural 7: dinner 18:00–22:00.
   - <seed=87> Shibuya→Asakusa→Harajuku sırası backtracking. Cluster'ı böldün.
   BUNLARI TEKRARLAMA.
   ```
4. Skor artmadıysa system prompt'a yeni bir madde eklemek gerek —
   davranışsal düzeltme yerine kural düzeltmesi. Prompt'u değiştir,
   `promptVersion` bump et, cache'i (`AiRouteReviewer`) invalidate et.
5. Bir sürüm ancak **arka arkaya 3 farklı seed'de ≥ 82 ortalama** verirse
   `docs/DECISIONS.md`'ye "prompt vN kabul edildi" olarak yazılır.

### 5. Adversarial senaryolar (regresyona karşı sabitlenir)

Bu senaryolar seed'siz, her koşumda çalışır:

- **A1** — Kyoto: 3 tapınak aynı cluster'da, 1 restoran 19:00 fixed,
  1 tapınak 17:00 kapanıyor. Model, tapınakları kapanış öncesi
  yerleştirmeli, akşamı restorana ayırmalı.
- **A2** — Tokyo çift cluster: Shibuya + Asakusa. Modelin cluster'ı
  bölmemesi bekleniyor (ROUTE_OPTIMIZATION.md testleriyle aynı ruh).
- **A3** — Hakone gün trip: Odawara'dan başla, ryokan'da bitir. Ropeway
  saat 17:00 kapanır, onsen saat 22:00 kapanır. Model ropeway'i öğleden
  önce, onsen'i akşam yemeğinden sonra koymalı.
- **A4** — Fizibilitesiz: 8 aktivite, günün toplam süresi 6 saat.
  Model `dropped[]` üretmeli, hepsini tıkıştırmaya çalışmamalı.
- **A5** — Öğle yemeği yok: Sadece 1 restoran ve o 20:00. Model
  `synthetic:meal` ile 12:00–13:00 arası cafe eklemeli VEYA `warnings`
  ile açıkça bildirmeli.
- **A6** — Metro aksaklığı: `reliability < 0.6` olan legler var.
  Model taksi alternatifi varsa taksi seçmeli.
- **A7** — Erken kapanış: `dayEnd = 20:00`. Akşam yemeği penceresi
  daralıyor; model dinner'ı 18:00–19:45 arasına sıkıştırmalı.

Her adversarial fail ise, düzeltme prompt'a **kalıcı kural** olarak
girer (Kural 7'ye alt-madde eklemek gibi).

### 6. Kod iskeleti (nereye koyulacak)

```
mobile/test/domain/route_prompt_e2e_test.dart      // ana test
mobile/test/fixtures/pois/<city>.json              // POI havuzu
mobile/test/fixtures/scenarios/adversarial/A*.json // sabit senaryolar
mobile/test/support/route_scenario_generator.dart  // rand üretici (seed'li)
mobile/test/support/route_hard_checker.dart        // hard constraint kontrolü
mobile/test/support/route_score.dart               // rubric skoru
docs/ROUTE_OPT_TEST_PROMPT.md                      // bu dosya (kanonik prompt)
```

AI çağrısı `AiRouteReviewer` üstünden gitmeli; test ortamında repository
override ile gerçek modele bağlanır, CI'da mock döner (mock çıktısı
determinstik BeamSearch sonucunu geri yollar — regresyon değil, sözleşme
testi çalışır).

### 7. Prompt versiyonlama

- `PROMPT_VERSION = "route-opt/v1.0.0"` — bu dosyanın başındaki commit.
- Her değişiklikte `MINOR` (kural eklendi/gevşedi), `MAJOR` (çıktı şeması
  değişti), `PATCH` (metin cilası).
- `AiRouteReviewer` cache anahtarına `PROMPT_VERSION` girer. Değişince
  eski cache otomatik invalidate.

---

## Özet

- **A bölümü** modele verilir — her senaryoda system prompt olarak birebir bu.
- **B bölümü** senin CI/entegrasyon iskeletin — rastgele senaryolar üretir,
  hard-constraint mekanik kontrolü, sonra 0–100 skor.
- 82 eşiği + 3-arka-arkaya-yeşil kuralı prompt'u "eğitilmiş" sayar.
- Adversarial 7 senaryo regresyon kilidi; onlar başarısızsa prompt patch'lenir.
- Deterministik `BeamSearchItineraryOptimizer` her zaman referans / benchmark
  olarak kalır; AI onun altında kalırsa o kalemden puan almaz.
