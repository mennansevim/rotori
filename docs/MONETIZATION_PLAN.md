# MONETIZATION_PLAN.md — Rotori Pro

> Rotori'nin para kazanma modeli, yayın kapsamı ve dağıtım stratejisi.
> Karar özeti `DECISIONS.md`'e, günlük iş `CURRENT_TASK.md`'ye işlenir.
>
> **Oluşturulma:** 2026-08-10 · **Branch:** `feat/premium-iap-foundation`
> **Durum:** Karar verildi, uygulanmaya hazır.
>
> Model kararı bu belgenin yazımı sırasında dört kez değişti. Gerekçe zinciri
> §9'da kayıtlı — **yeniden tartışmadan önce §9 okunmalı.**

---

## 1. Durum tespiti (2026-08-10)

Kod tabanından doğrulanan gerçekler:

| Alan | Durum | Kanıt |
|---|---|---|
| App Store yayını | **Yok.** Hiç yayınlanmamış | `pubspec.yaml` `version: 1.0.0+1`; `rotori-mobile/docs/IOS_RELEASE_MANUAL_GATE_CHECKLIST.md` içinde işaretli kutu yok; fastlane/metadata yok |
| Ödeme altyapısı | **Yok.** `in_app_purchase` / RevenueCat bağımlılığı yok | `rotori-mobile/pubspec.yaml` |
| Premium yetkisi (istemci) | **Sadece debug anahtarı.** `debug_premium` prefs, `kDebugMode` ile gizli | `lib/features/plans/premium_provider.dart`, `lib/features/plans/widgets/plan_viewer_drawer.dart:202` |
| Premium yetkisi (sunucu) | **Okuma tarafı hazır, yazan yok.** `is_premium()` → `auth.users.raw_user_meta_data->>'premium'` | `supabase/migrations/0008_daily_scans.sql` |
| Tarama kotası | **Çalışıyor, sunucuda zorlanıyor.** free 10 / premium 100, `tag_cache` tekrar çağrıyı önlüyor | `0008_daily_scans.sql`, `supabase/functions/parse-price-tag/index.ts:176` |
| Rota optimizasyonu kilidi | **Coming-soon duvarı, satış değil.** Kilit istemcide → bypass edilebilir | `lib/core/l10n.dart:2646`, `lib/features/plans/plan_viewer_screen.dart:4055` |
| Optimizasyon kazanç verisi | **Var.** `totalTravelMinutes` öncesi/sonrası hesaplanıyor | `lib/features/plans/plan_optimization_controller.dart:44` |
| Offline tile önbelleği | **Var ama tek gün.** `prewarmTiles()` yazılmış, 400 tile üst sınırı | `lib/features/viewer/offline_tile_provider.dart:133` |
| Lokalizasyon | **%100 iki dilli.** TR 1240 / EN 1240 anahtar | `lib/core/l10n.dart` |
| Gezi limiti | **Yok.** Sınırsız gezi oluşturulabiliyor | `lib/features/plans/plans_list_screen.dart` |
| Sosyal kanal | **Açık, erken aşama.** @japonyaruyasi yayında (10–15 video), ~1000 video arşivi + otomatik hat kurulu ama hat yalnızca 2 gönderi yapmış; `topic` otomasyonu `enabled: false` | `rotori-social/data/instagram_uploads.jsonl`, `automation_config.json` |
| Web planner | **Atıl.** Legacy React planner bakım modunda | `rotori-website/legacy/apps/planner/` |
| Değişken maliyet | **İhmal edilebilir.** Tarama başına ≈ ₺0.02 (gpt-4o-mini) | `parse-price-tag/index.ts:11`, `fetch-tr-prices/index.ts:9` |

**Bundan çıkan sonuç:** Gelir = `indirme × dönüşüm × fiyat × (1 − komisyon)`. Fiyat
dışındaki her terim sıfır veya ölçülmemiş. Darboğaz **fiyat değil dağıtım**.
Kota da maliyet kaynaklı değil (100 taramanın maliyeti ₺2) — bir dönüşüm kolu.

---

## 2. Pazar araştırması — kararların kanıt temeli

### 2.1 Benzer uygulamalar

| Uygulama | Model | Fiyat | Not |
|---|---|---|---|
| TripIt Pro | Abonelik | $49/yıl | Ücretsiz itinerary kurar; Pro seyahat *sırasında* bilgi verir |
| Wanderlog Pro | Abonelik + affiliate | $29.99–49.99/yıl | Offline erişim, Maps'e aktarma, uçuş takibi paywall'da; otel/uçuş komisyonu da alıyor |
| Tripsy Pro | Abonelik + lifetime | $59.99/yıl, $9.99/ay, lifetime **$299** | Lifetime yıllığın **5 katı** — ana ürün değil, çıpa |
| Japan Travel (NAVITIME) | Freemium abonelik | ~¥330/ay | Japonya nişinin en güçlü oyuncusu; offline harita + AI itinerary analizi |

**Hiçbiri gezi başına satmıyor.** Bu kadar denenmiş bir kategoride "trip pass"
boşluğunun olması, o modelin çalışmadığının işareti.

### 2.2 Kategori kıyaslamaları (RevenueCat 2026, 115.000+ uygulama)

Seyahat kategorisi:

- **Aboneliklerin %66'sı yıllık satılıyor** — pazar ortalaması %34.
  Seyahat, tüm kategoriler arasında **en yıllık-ağırlıklı** kategori
- **Deneme→ödeme dönüşümü %43,5 medyan** — kategoriler arasında en yükseklerden
- **%51,2'si "mixed trial" kullanıyor** (bazı özellik açık, bazısı paywall'da);
  yalnızca %4,1'i saf deneme
- **İndirme→ödeme (D35) medyanı %2,0** (tüm kategoriler)
- **$1K aylık gelire ulaşma süresi medyan 238 gün**
- **Yeni seyahat uygulamalarının yalnızca %9,8'i 2 yılda $10K MRR'a ulaşıyor**
- **Seyahat en ucuz kategori**: yıllık medyan fiyat $20

### 2.3 Wanderlog nasıl 3,6–5 milyon indirmeye çıktı

Reklamla değil: kullanıcı itinerary'lerini **herkese açık ve Google'da
indekslenebilir** hale getirerek. Organik web trafiğinin **%60'ından fazlası**
"7 günlük Tokyo rotası" gibi long-tail aramalardan geliyor.

Bu, Rotori için doğrudan uygulanabilir — atıl duran web planner'ı var (§6.2).

---

## 3. Model kararı — yıllık-öncelikli abonelik

### 3.1 SKU'lar

Abonelik grubu `rotori_pro`, **her ikisinde 7 gün ücretsiz deneme**:

| Ürün ID | Tip | TR | Global | Yayın |
|---|---|---|---|---|
| `...japanTrip.pro.yearly` | Auto-renewable, 1 yıl | **₺499** | **$29.99** | **v1.0** — varsayılan seçili, "en avantajlı" |
| `...japanTrip.pro.monthly` | Auto-renewable, 1 ay | ₺99 | $4.99 | **v1.1'e ertelendi** (§4.2) |

Komisyon: Small Business Program ile **%15 sabit**.

Fiyat gerekçesi: seyahat en ucuz kategori ($20/yıl medyan) → ₺599 yerine ₺499.
Global $29.99 Wanderlog bandında, medyanın hafif üstünde; Japonya'ya özel
derinlik bunu taşır. Aylık geldiğinde ₺99 × 12 = ₺1.188 vs ₺499 → "%58
tasarruf" çıpası. **Fiyat deneyi TR'de değil global $ tarafında yapılır.**

Tek seferlik "lifetime" **eklenmez** (üç seçenek dönüşümü düşürür; Tripsy'de
bile 5x fiyatla çıpa rolünde).

### 3.2 Ücretsiz / Pro sınırı

Ücretsiz kalır — mağaza puanı ve ağızdan ağıza yayılma motoru:

- 66 yemeklik Japon mutfağı rehberi (`eats_screen.dart` — **paywall'a asla geri
  konmaz**, bkz. `premium_gates_test.dart` sözleşmesi)
- Japonca ifadeler, "Mutlaka Bilmeniz Gerekenler", acil durum bilgileri
  (**dil yardımı ve acil durum bilgisi paywall arkasına konmaz**)
- Hava durumu, pusula, checklist, statik bütçe tahmini
- **Plan oluşturma** — tarihler, şehirler, tercihler, tahmini bütçe
- **Ön izleme:** ilk gün + "bu plan sana X saat kazandırıyor" (§5.3)
- 1 aktif gezi · 10 tarama/gün

Pro:

- Planın tüm günleri, saatli ve optimize edilmiş rota
- Rota optimizasyonu (sınırsız)
- Tüm gezinin offline harita paketi
- Sınırsız gezi · 100 tarama/gün + TR pazar fiyat karşılaştırması
- Bilet/evrak kasası · planlama fazı araçları · ekiple paylaşım

---

## 4. Yayın kapsamı

### 4.1 v1.0 — minimal, 12–14 gün

Araştırmadaki sayılar (indirme→ödeme %2, $1K MRR'a 238 gün) sıfır kullanıcılı
bir uygulamaya 26 gün ödeme altyapısı yazmayı yanlış yatırım yapıyor. Ama
tamamen bedava yayınlayıp sonra paywall eklemek de yanlış (grandfathering).
**Çözüm: kapıları tak, ama sadece gerekli olanları.**

| Faz | İş | Gün |
|---|---|---|
| 0 | App Store Connect + SBP | 0.5 |
| 1 | IAP + receipt doğrulama + S2S — **yalnızca yıllık** | 4–5 |
| 2 | Paywall + Apple uyumu + gate'in sunucuya taşınması | 2–3 |
| 3 | Ön izleme hunisi + "kazandırdığı saat" + gezi limiti | 2.5 |
| 4 | Release gate + sandbox testi | 3–5 |
| | **Toplam** | **12–14** |

### 4.2 v1.0'dan çıkarılanlar

Hiçbiri şu an ücretsiz değil → sonra eklemek "geri alma" yaratmaz:

- Aylık SKU (yıllık tek başına yeter; %66 yıllık verisi bunu destekliyor)
- Offline tüm gezi harita paketi
- Planlama fazı retention araçları (kur takibi, harcama girişi, zamanlı hatırlatma)
- Bilet/evrak kasası
- Ekiple paylaşım

---

## 5. Fazlar

### Faz 0 — Hazırlık (0.5 gün) · kod gerektirmez

- [ ] App Store Connect: abonelik grubu `rotori_pro` + `...pro.yearly`
- [ ] Yıllığa **7 gün ücretsiz deneme** introductory offer
- [ ] Small Business Program başvurusu (%30 → %15)
- [ ] `docs/DECISIONS.md`'e karar kaydı (bu belgeye referans)
- [ ] `docs/CLAUDE.md` §1'deki "ücretsiz reklamsız MVP" ifadesi güncellenir

**Kabul:** Ürün "Ready to Submit", deneme teklifi tanımlı.

---

### Faz 1 — Abonelik altyapısı (4–5 gün)

Tamamı yeni `lib/features/premium/` paketinde.

**1.1 İstemci**
- [ ] `in_app_purchase: ^3.2.0` → `pubspec.yaml`
- [ ] `purchase_service.dart`: ürün sorgulama, satın alma, `purchaseStream`
      (pending/purchased/error/canceled), `restorePurchases()`
- [ ] Hata durumları: mağaza erişilemez, ürün yok, ödeme reddedildi,
      pending (Ask to Buy / SCA), ağ yok
- [ ] **Deneme uygunluğu**: kullanıcı denemeyi kullandıysa paywall
      "7 gün ücretsiz" demez (yanlış vaat = red riski)

**1.2 Sunucu doğrulama**
- [ ] `supabase/functions/verify-purchase/index.ts` — App Store Server API
      (JWS `signedTransactionInfo`); legacy `/verifyReceipt` kullanılmaz
- [ ] `bundleId` / `productId` / `transactionId` / **`expiresDate`** kontrolü
- [ ] **Replay koruması:** `transactionId` tekilliği DB'de zorlanır
- [ ] `supabase/migrations/0009_subscriptions.sql` — `public.subscriptions`
      (`user_id`, `original_transaction_id` unique, `product_id`, `status`,
      `expires_at`, `is_trial`, `platform`, `raw_payload`); RLS: self-read,
      INSERT/UPDATE yalnız service_role
- [ ] **`is_premium()` güncellenir** — artık bayrak *ve* `expires_at > now()`
      (grace period toleransı dahil)
- [ ] **Apple S2S Notifications V2 endpoint'i — zorunlu.** `DID_RENEW`,
      `EXPIRED`, `DID_FAIL_TO_RENEW`, `GRACE_PERIOD_EXPIRED`, `REFUND`,
      `REVOKE`, `DID_CHANGE_RENEWAL_STATUS`. Onsuz iptal/iade sonrası erişim
      süresiz açık kalır

**1.3 `premiumProvider` yeniden yazımı**
- [ ] Tek doğru kaynak **sunucu**: Supabase metadata + `expires_at`
- [ ] Prefs yalnızca **offline cache**; süre de yazılır, süresi geçmiş cache
      Pro açmaz
- [ ] `kPremiumPrefsKey` → `'premium_entitlement_cache'`; debug override ayrı
      anahtara (`'debug_premium_override'`), yalnız `kDebugMode` altında
- [ ] `premium_gates_test.dart` güncellenir — mevcut hâli prefs sözleşmesini
      kilitliyor (satır 67–71), **kasıtlı kırılacak**, yeni sözleşmeye yazılacak

**Kabul:** Sandbox'ta deneme başlatma → kayıt → kilitler açık · hızlandırılmış
yenileme `expires_at` ilerletiyor · iptal + süre bitimi erişimi kapatıyor ·
iade erişimi anında kapatıyor · "Geri Yükle" çalışıyor · aynı işlem idempotent ·
çevrimdışı geçerli abone kilit görmüyor, süresi geçmiş cache Pro açmıyor ·
release build'de debug override okunmuyor (test ile kanıtlı).

---

### Faz 2 — Paywall ve mağaza uyumu (2–3 gün)

- [ ] `paywall_screen.dart`
  - **fiyat mağazadan okunur**, koda gömülmez
  - "7 gün ücretsiz dene" CTA, deneme uygunluğuna göre değişen kopya
  - **Apple'ın zorunlu abonelik açıklaması** (sık red sebebi): abonelik
    uzunluğu, dönem fiyatı, otomatik yenileme dili, denemeden sonra
    ücretlendirileceği, iptalin nasıl yapılacağı
  - "Satın alımları geri yükle" + Kullanım Şartları + Gizlilik linkleri
  - TR + EN kopya (`premium.*` l10n anahtarları)
- [ ] `l10n.dart:2646` `routeOptimization.premium.body` — "sunulacak" ifadesi
      kaldırılır, gerçek satış diline geçilir
- [ ] `_showPremiumSheet` (`scanner_screen.dart:695`) yeni paywall'a yönlenir;
      iki ayrı premium anlatısı kalmaz
- [ ] Ayarlarda "Aboneliği yönet" → sistem sayfası
- [ ] `rotori-website`: fiyatlandırma bölümü + **Gizlilik Politikası ve
      Kullanım Şartları sayfaları** (App Store'un istediği URL'ler)
- [ ] **Güvenlik:** rota optimizasyonunun AI POI keşif çağrısı Edge Function'a
      taşınır, orada `is_premium()` kontrolü. Şu an kilit tamamen istemcide
      (`plan_viewer_screen.dart:4055`), prefs düzenlemesiyle aşılabilir.
      Yerel deterministik motor istemcide kalabilir; **ücretli yüzey sunucuda
      korunur**

**Kabul:** Apple abonelik maddeleri karşılanmış; premium olmayan istemci elle
prefs değiştirerek AI çağrısı yapamıyor.

---

### Faz 3 — Ön izleme hunisi ve limitler (2.5 gün)

Araştırmanın en yüksek dönüşüm kalemi. Kategorinin %51,2'si "mixed trial"
kullanıyor — ön izleme + deneme birbirinin alternatifi değil, aynı hunide
üst üste iki adım.

**3.1 Ön izleme hunisi (1.5 gün)**
```
Ücretsiz plan oluşturma (tarih, şehir, tercih, tahmini bütçe)
        ↓
Kişiselleştirilmiş ön izleme: 1. gün açık + kalan günler bulanık
"Bu plan sana 6 sa 40 dk ulaşım kazandırıyor"
        ↓
7 gün ücretsiz deneme → tüm plan açık
        ↓
Yıllık aboneliğe dönüşüm
```
- [ ] Ödeme duvarı **uygulama açılışına konmaz**; kullanıcı önce kendi
      sonucunu görür
- [ ] Kalan günler kilitli ama **görünür** (kaç durak, hangi şehir) — boş
      kilit değil, dolu kilit

**3.2 "Kazandırdığı saat" göstergesi (0.5 gün)**
- [ ] `totalTravelMinutes` öncesi/sonrası farkı
      (`plan_optimization_controller.dart:44` — veri hazır)
- [ ] Ön izlemede ve paywall'da değer ifadesi olarak gösterilir
- [ ] "Optimize rota" soyut; "6 sa 40 dk kazandırıyor" satın alma gerekçesi

**3.3 Gezi limiti (0.5 gün) — ertelenemez**
- [ ] 1 aktif gezi ücretsiz, 2.+ Pro
- [ ] **Mevcut kullanıcı yok** → grandfathering sorunu yok. Yayından *önce*
      konmalı, sonra koymak imkânsız

---

### Faz 4 — Yayın (3–5 gün) · gerçek kritik yol

- [ ] `IOS_RELEASE_MANUAL_GATE_CHECKLIST.md` **baştan sona tamamlanır** — şu an
      tek kutu işaretli değil. P0 maddeleri (release build smoke, auth route
      güvenliği, Apple Sign-In capability, plan veri bütünlüğü, permission
      açıklamaları) yayın blokeri
- [ ] Gerçek cihaz matrisi: küçük iPhone + modern iPhone + iPad
- [ ] Sandbox abonelik testi: deneme, hızlandırılmış yenileme, iptal, süre
      bitimi, iade, Ask to Buy, restore
- [ ] App Store metadata TR + EN: isim, altyazı, anahtar kelimeler
      ("Japonya", "Japan trip planner", "Japan itinerary"), açıklama
      (+ abonelik bilgisi zorunlu)
- [ ] Ekran görüntüleri — **tarayıcının AR overlay'i ilk görsel**
- [ ] `version` 1.0.0+1'den yükseltilir; bundle id korunur

---

### Faz 4.5 — Kapalı lansman (yayından hemen sonra)

20 kullanıcı elle bulunur, birebir konuşulur. Ölçülecek beş soru:

1. Planı nerede anlamadılar?
2. Neyi gereksiz buldular?
3. Hangi özellik için ödediler?
4. ₺499'u pahalı mı makul mu buldular?
5. Planı **Japonya'da gerçekten kullandılar mı?**

Bu 20 görüşme, planlama-fazı-tutunması sorusunu hiçbir kıyaslama verisinin
cevaplayamadığı şekilde cevaplar. Açık lansman öncesi zorunlu kapı.

---

## 6. Dağıtım stratejisi

Gelirin fiyattan değil buradan geleceğini kabul eden bölüm.
**Faz 1 ile paralel başlar.**

### 6.1 Video hattı (haftada 3)

- [ ] @japonyaruyasi'da **otomasyon devreye alınır** — kanal yayında (10–15
      video) ama gönderiler elle; hat 2 gönderi üretmiş.
      `automation_config.json`'da `topic: enabled false` → açılır
- [ ] TikTok cross-post açılır (`tiktok_publisher.py` hazır)
- [ ] **Problem odaklı hook'lar** (özellik demosu değil):
  - "Tokyo'da aynı güne koymamanız gereken 3 yer"
  - "Japonya'da yapılan en pahalı ulaşım hatası"
  - "JR Pass gerçekten gerekli mi?"
  - "10 günlük Japonya rotası nasıl bölünür?"
  - "ChatGPT'nin Japonya planlarında yaptığı 5 hata"
- [ ] Hepsi tek çağrıyla biter: "Ücretsiz Japonya rota ön izlemeni oluştur"
- [ ] Her videoda App Store linki
- [ ] **EN içerik kuyruğu** — l10n hazır, global pazar 10 kat

### 6.2 SEO motoru — uzun vadede en değerli kanal

Wanderlog'un 5M indirmeye çıkma yolu (§2.3). Videonun tersine **birikimli**:
bir video 48 saatte ölür, indekslenmiş sayfa yıllarca trafik getirir.

- [ ] Atıl legacy web planner (`rotori-website/legacy/apps/planner/`) herkese
      açık, indekslenebilir rota sayfalarına çevrilir
- [ ] Hedef long-tail sorgular: "10 günlük Japonya rotası", "Tokyo Kyoto Osaka
      kaç gün", "Japonya 2 hafta bütçesi"
- [ ] Ürünün **kendi çıktısı** indekslenir — elle içerik üretilmez
- [ ] Her sayfada uygulamaya CTA

**Uyarı:** Bu bir checkbox değil, proje büyüklüğünde iş (legacy React, bakım
modunda, statik hosting). Kararı şimdi verilir, yayından sonra yapılır — ama
**plan veri modeli bugünden dışa aktarılabilir tutulursa** sonra ucuza gelir.

### 6.3 Affiliate katmanı — ikincil gelir

Wanderlog'un abonelik yanında yaptığı şey; kullanıcı başına IAP'den hızlı
getirebilir ve build maliyeti neredeyse sıfır.

- [ ] eSIM (her Japonya gezgini alıyor, komisyon %15–20 bandında)
- [ ] JR Pass / bölgesel paslar
- [ ] Otel rezervasyonu
- [ ] Checklist ve "Mutlaka Bilmeniz Gerekenler" ekranlarına yerleştirilir

---

## 7. Metrikler ve gerçekçi beklenti

| Metrik | Neden | Kaynak |
|---|---|---|
| İndirme (TR / global ayrı) | Çarpımın ilk terimi | App Store Connect |
| D1 / D7 tutunma | Tutunma yoksa dönüşüm de olmaz | Connect |
| **Plan oluşturma → ön izleme tamamlama** | Hunideki ilk gerçek adım | Kendi log'u |
| **Ön izleme → deneme başlatma** | Üst huni | Kendi log'u + Connect |
| **Deneme → ödemeye dönüşüm** | Aboneliğin en kritik tek sayısı (kategori medyanı %43,5) | Connect |
| Hangi özellikten paywall'a gelindi | Hangi Pro özelliği satıyor | Kendi log'u |
| Aylık churn / ortalama abone ömrü | ARPU'yu belirler | Connect |
| İade oranı | %3'ü aşarsa fiyat/vaat uyumsuz | Connect |
| Tarama başına LLM maliyeti | Marj takibi | OpenAI + `daily_scans` |

**Beklenti — dürüst:** 1. yılda anlamlı gelir beklenmemeli. Kategori medyanı
$1K MRR için 238 gün, indirme→ödeme %2, yeni seyahat uygulamalarının %9,8'i
2 yılda $10K MRR görüyor. Gerçekçi 1. yıl çıktısı: **yayınlanmış ürün,
doğrulanmış fiyat, birikmeye başlamış SEO varlığı.**

Kısa vadede nakit hedefi varsa doğru araç bu değil — o durumda affiliate
katmanı (§6.3) öne alınır.

---

## 8. Riskler

| Risk | Etki | Azaltma |
|---|---|---|
| **Dağıtım açılmazsa gelir sıfır kalır** | Kritik | §6 opsiyonel değil, Faz 1 ile paralel başlar |
| Apple abonelik uyum reddi | Yüksek, 1–2 hafta | Faz 2'de zorunlu maddeler baştan takılır |
| **Süre/yenileme hataları** (iptal sonrası erişim açık) | Yüksek, gelir sızıntısı | S2S V2 Faz 1.2'de zorunlu; `expires_at` `is_premium()`'a girer |
| Planlama fazı tutunmazsa churn yüksek olur | Orta | Yıllık SKU riski satın alma anında kapatır; Faz 4.5 gerçek veriyi getirir |
| Prefs ile premium bypass | Orta | Faz 2'de ücretli yüzey sunucuya taşınır |
| Pazar küçüklüğü (TR-only) | Yüksek | EN zaten hazır; §6.1 EN kuyruğu + §6.2 SEO |
| TL enflasyonu fiyatı eritir | Orta | Yıllık peşin tahsilat korur; TL fiyatı dönemsel gözden geçirilir |
| Rakip (NAVITIME, Wanderlog, Klook, Google Maps) | Orta | Ayrışma: TR dili + Japonya derinliği + tarayıcılar + diyet/helal bilgisi |
| Deneme suistimali | Düşük | Apple deneme uygunluğunu hesap başına yönetiyor |

---

## 9. Karar günlüğü — yeniden tartışmadan önce okunmalı

Model kararı bu belgenin yazımı sırasında dört kez değişti. Zincir:

1. **Tek seferlik ₺449** — gerekçe: gezi tek seferlik bir olay, abonelik
   churn/iade riski taşır. *Sezgiye dayalıydı.*
2. **Yıllık ₺599 abonelik** — kullanıcı itirazı: "6 ay önce alıp gezi sonrası
   iptal ederler, daha çok kazandırır." Belirleyici yeni bilgi: **Apple'da
   ücretsiz deneme yalnızca aboneliklerde mümkün.**
3. **Tek seferlik ₺499** — ChatGPT önerisi: kişiselleştirilmiş ön izleme
   hunisi. Varsayım: ön izleme, denemeyi gereksiz kılar. *Bu varsayım yanlıştı.*
4. **Yıllık ₺499 abonelik + ön izleme hunisi** ← **geçerli karar.**
   Pazar verisi: seyahat aboneliklerinin %66'sı yıllık (en yıllık-ağırlıklı
   kategori), deneme→ödeme %43,5, kategorinin %51,2'si ön izleme *ve* denemeyi
   **birlikte** kullanıyor. Ön izleme denemenin alternatifi değil, aynı hunide
   üst üste iki adım. Ayrıca hiçbir başarılı benzer uygulama gezi başına
   satmıyor; lifetime sunanlar onu yıllığın 5 katı fiyatla çıpa olarak
   konumluyor.

**Bu kararı tekrar açmak için gereken:** §2.2'deki kıyaslamaları çürüten yeni
veri, ya da Faz 4.5 görüşmelerinden gelen aksi yönde gerçek kullanıcı sinyali.
Sezgi yeterli değil — dört turun gösterdiği şey bu.

---

## 10. Kaynaklar

- [RevenueCat — State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps)
- [RevenueCat — State of Subscription Apps 2025](https://www.revenuecat.com/state-of-subscription-apps-2025)
- [Tripsy Pro fiyatlandırma](https://tripsy.app/pro)
- [TripIt Pro fiyatlandırma](https://www.tripit.com/web/pro/pricing)
- [Wanderlog — App Store](https://apps.apple.com/us/app/wanderlog-travel-planner/id1476732439)
- [Wanderlog Pro fiyat analizi 2026](https://monkeyeatingmango.com/blog/wanderlog-pricing-2026/)
- [Wanderlog büyüme/pazarlama stratejisi](https://businessmodelcanvastemplate.com/blogs/marketing-strategy/wanderlog-marketing-strategy)
- [Japan Travel by NAVITIME](https://www.jrailpass.com/blog/japan-navitime-how-to-use)
- [Indie seyahat uygulamaları gelir modelleri](https://www.anything.com/blog/travel-app-ideas)
