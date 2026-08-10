# MONETIZATION_PLAN.md — Rotori Pro

> Rotori'nin para kazanma modeli, yayın kapsamı ve dağıtım stratejisi.
> Karar özeti `DECISIONS.md`'e, günlük iş `CURRENT_TASK.md`'ye işlenir.
>
> **Oluşturulma:** 2026-08-10 · **Branch:** `feat/premium-iap-foundation`
> **Durum:** **Lansmanda test edilecek hipotez** — doğrulanmış nihai model değil.
>
> Rotori lansmanda ₺499/yıl + ₺99/ay abonelik modelini test edecektir. İlk
> **100–200 nitelikli kullanıcının** satın alma ve kullanım verisinden sonra
> trip-pass, abonelik veya hibrit model arasında yeniden değerlendirilecektir.
>
> Model kararı bu belgenin yazımı sırasında dört kez değişti. Gerekçe zinciri
> ve kanıtın **sınırları** §9'da kayıtlı — **yeniden tartışmadan önce §9 okunmalı.**

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

**Hiçbiri gezi başına satmıyor.** Bu, trip-pass modelinin çalışmadığını
**kanıtlamaz** — kanıtın yokluğu yokluğun kanıtı değildir. Gösterdiği şey şu:
trip-pass'i *ana model* olarak seçmek için elimizde pazar kanıtı yok, oysa
aboneliğin bu kategoride çalıştığına dair bol kanıt var. Bu yüzden abonelikle
başlanır; trip-pass hipotez olarak açık kalır (§9).

### 2.2 Kategori kıyaslamaları (RevenueCat 2026, 115.000+ uygulama)

> **⚠ Bu verinin sınırları — okumadan sonuç çıkarma:**
>
> 1. **Seçim yanlılığı.** RevenueCat bir abonelik altyapısı şirketidir; veri
>    yalnızca **abonelik kullanan** uygulamalardan gelir. Tek seferlik satan
>    uygulamalar veri kümesinde yoktur. Dolayısıyla bu veri *"seyahatte
>    aboneliği nasıl iyi yaparsın"* sorusunu cevaplar,
>    **"abonelik gezi-başına modelden iyi midir" sorusunu cevaplayamaz.**
> 2. **%66 yıllık içsel (endojen) bir sayıdır.** Uygulamaların *sattığını*
>    ölçer; çoğu seyahat uygulaması yıllığı varsayılan + "en avantajlı" olarak
>    sunduğu için bu sayı kullanıcı tercihi ile paywall tasarımını ayrıştırmaz.
> 3. **%43,5 hunideki son adımdır** — indirenlerin değil, *denemeyi
>    başlatanların* ödemeye dönüşme oranı. Öncesinde indirme → plan
>    tamamlama → paywall görme → deneme başlatma adımları var ve kayıp orada.

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

Kategoriden bağımsız iki sayı, tasarımı doğrudan etkiliyor:

- **Denemelerin %82'si kurulumla aynı gün başlıyor** → ön izleme hunisi
  **ilk oturumda** değeri göstermek zorunda. Sonraki oturuma bırakılan
  değer gösterimi çoğu kullanıcıya hiç ulaşmaz.
- **Yıllık aboneliklerin ~%30'u ilk ay içinde iptal ediliyor.** Not: iptal
  ≠ iade — otomatik yenileme kapanır, 1. yıl geliri durur. Yani "yıllık =
  peşin tahsilat" avantajı 1. yıl için geçerli, ama **2. yıl LTV'si kırılgan**
  ve sürekli değer üretmeyi gerektiriyor.

### 2.3 Wanderlog nasıl 3,6–5 milyon indirmeye çıktı

Reklamla değil: kullanıcı itinerary'lerini **herkese açık ve Google'da
indekslenebilir** hale getirerek. Organik web trafiğinin **%60'ından fazlası**
"7 günlük Tokyo rotası" gibi long-tail aramalardan geliyor.

Bu, Rotori için doğrudan uygulanabilir — atıl duran web planner'ı var (§6.2).

---

## 3. Model kararı — yıllık-öncelikli abonelik

### 3.1 SKU'lar

Abonelik grubu `rotori_pro`, **ikisi de v1.0'da**:

| Ürün ID | Tip | TR | Global | Deneme | Paywall'daki rol |
|---|---|---|---|---|---|
| `...japanTrip.pro.yearly` | Auto-renewable, 1 yıl | **₺499** | **$29.99** | **7 gün ücretsiz** | Varsayılan seçili, "en avantajlı" |
| `...japanTrip.pro.monthly` | Auto-renewable, 1 ay | **₺99** | **$4.99** | Yok | Görünür, gizlenmez |

Komisyon: Small Business Program ile **%15 sabit**.

**Deneme neden yalnızca yıllıkta:** Deneme almak isteyen kullanıcıyı yüksek
LTV'li yıllığa yönlendirir; aylık, denemesiz bir "düşük taahhüt" seçeneği
olarak kalır.

**Aylık neden v1.0'da (gizlenmiyor):** Aylık/yıllık dağılımı, kullanıcının
Rotori'yi **tek-gezi aracı mı sürekli hizmet mi** gördüğünü söyleyen tek
gerçek veri. Bu, §9'da açık bırakılan trip-pass hipotezini besleyen ölçümdür —
aylık payı yüksek çıkarsa gezi-başına model yeniden değerlendirilir.

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
| 0 | App Store Connect (yıllık + aylık, S2S URL'leri, Server API anahtarı) + SBP | 0.5 |
| 0.5 | **Hedef kullanıcı görüşmeleri** (10–20, kod gerektirmez) | paralel |
| 1 | Abonelik altyapısı — üç tablolu şema, JWS + `appAccountToken`, S2S durum makinesi + reconciliation, istemci + kalıcı retry, hukuki metinler | **6–9** |
| 2 | Paywall + Apple uyumu + gate'in sunucuya taşınması | 2–3 |
| 3 | Ön izleme hunisi + "kazandırdığı saat" + gezi limiti | 2.5 |
| 4 | Release gate + sandbox senaryo matrisi | 3–5 |
| | **Toplam** | **15–20** |

> Faz 1 ilk tahmini 4–5 gündü; dış inceleme (2026-08-10) kapsamı genişletti:
> üç tablolu işlem/entitlement/notification şeması, `appAccountToken` hesap
> sahipliği, S2S durum makinesi + reconciliation, `completePurchase()` +
> kalıcı doğrulama kuyruğu, deneme uygunluğunun StoreKit 2 API'sinden
> okunması, hesap silme çakışması ve eksik Kullanım Şartları sayfası.
> Mimari sözleşme: `ARCHITECTURE.md` §8b.

### 4.2 v1.0'dan çıkarılanlar

Hiçbiri şu an ücretsiz değil → sonra eklemek "geri alma" yaratmaz:

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
  - **İki SKU yan yana**: yıllık varsayılan seçili + "en avantajlı",
    aylık görünür (gizlenmez). "%58 tasarruf" karşılaştırması
    (₺99 × 12 = ₺1.188 vs ₺499)
  - **fiyat mağazadan okunur**, koda gömülmez
  - "7 gün ücretsiz dene" CTA **yalnızca yıllıkta**; aylıkta doğrudan satın alma
  - deneme uygunluğuna göre değişen kopya
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
- [ ] **İlk oturumda tamamlanmalı.** Denemelerin %82'si kurulumla aynı gün
      başlıyor; ikinci oturuma bırakılan değer gösterimi çoğu kullanıcıya
      hiç ulaşmaz
- [ ] **Deneme kısıtlanmaz.** Deneme sırasında kullanıcı planın tamamını
      görür, düzenler, bütçe ve rota araçlarını kullanır. Denemeyi
      işlevsizleştiren kısıtlama dönüşümü değil güveni öldürür

**3.2 "Kazandırdığı saat" göstergesi (0.5 gün)**
- [ ] `totalTravelMinutes` öncesi/sonrası farkı
      (`plan_optimization_controller.dart:44` — veri hazır)
- [ ] Ön izlemede ve paywall'da değer ifadesi olarak gösterilir
- [ ] "Optimize rota" soyut; "6 sa 40 dk kazandırıyor" satın alma gerekçesi
- [ ] **Dürüstlük şartı — pazarlama için şişirilmez.** Sayı yalnızca
      güvenilir bir önce/sonra hesabından gelir. Somut kural:
      `PlanOptimizationController` infeasible durumlarda
      (`noFeasibleRoute` / `routeDataMissing` / `fixedConflict` /
      `protectedInfeasible`) **yerel kural tabanlı fallback preview**
      üretiyor (bkz. CURRENT_TASK 2026-08-06). O yoldan gelen sonuçta
      kazanç sayısı **gösterilmez** — fallback'te matris verisi güvenilir
      değil. Uydurma bir sayı, `uyum skoru artık bilmediğini uydurmuyor`
      (af6f721) ve ramen düzeltmesi (d0a661f) ile kurulan ürün ilkesini bozar

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

### Faz 0.5 / 4.5 — Kullanıcı görüşmeleri (iki dalga)

**Dalga 1 — yayından ÖNCE (Faz 1 ile paralel, kod gerektirmez).**
10–20 hedef kullanıcı (Japonya'ya gitmeyi planlayan kişi) bulunur; ücretsiz
katmanın TestFlight build'i ya da ekran akışı gösterilir. Amaç **dil ve
itirazları çıkarmak**: hangi kelimeyi anlamıyorlar, neyi gereksiz buluyorlar,
"neden ödeyeyim" itirazı nereden geliyor. Çıktısı doğrudan paywall kopyasına
ve ön izleme tasarımına girer.

**Dalga 2 — yayından sonra, gerçek ödeyen kohortu.** Ölçülecek beş soru:

1. Planı nerede anlamadılar?
2. Neyi gereksiz buldular?
3. Hangi özellik için ödediler?
4. ₺499'u pahalı mı makul mu buldular?
5. Planı **Japonya'da gerçekten kullandılar mı?**

**Görüşmelerin sınırı — fazla yüklenmeyin:** Görüşme **fiyatı doğrulamaz**;
yalnızca dili, itirazları ve kullanım gerçekliğini ortaya çıkarır. Fiyatı
doğrulayan tek veri **gerçek ödeme ekranındaki davranıştır** (§7).

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

Bu, monetizasyon planının alt maddesi olamayacak kadar büyük ve ayrı bir
yürütme mantığı var → **`docs/GROWTH_SEO_STRATEGY.md`**.

Buradan bilinmesi gereken tek bağlantı: **plan veri modeli bugünden dışa
aktarılabilir tutulursa** SEO hattı sonra ucuza gelir. Faz 3'te ön izleme
hunisi yazılırken plan çıktısının serileştirilebilir kalmasına dikkat edilir.

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
| **İlk 24 saatte deneme iptali** | Denemenin içeriği hayal kırıklığı yarattıysa burada görünür | Connect |
| **Aylık / yıllık paket dağılımı** | Kullanıcı Rotori'yi tek-gezi aracı mı sürekli hizmet mi görüyor → trip-pass hipotezinin testi (§9) | Connect |
| **Gezi sırasında uygulamayı kullananlar** | Ürünün gerçek değer testi; abonelik yenilemesinin ön koşulu | Kendi log'u |
| Hangi özellikten paywall'a gelindi | Hangi Pro özelliği satıyor | Kendi log'u |
| Aylık churn / ortalama abone ömrü | ARPU'yu belirler | Connect |
| İade ve destek talepleri | %3'ü aşarsa fiyat/vaat uyumsuz | Connect |
| Tarama başına LLM maliyeti | Marj takibi | OpenAI + `daily_scans` |

**Toplam indirme birincil metrik DEĞİL.** Başlangıçta yukarıdaki zincir
ölçülür; indirme yalnızca zincirin denominatörüdür.

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
4. **Yıllık ₺499 + aylık ₺99 abonelik + ön izleme hunisi** ←
   **lansmanda test edilecek hipotez.**
   Pazar verisi: seyahat aboneliklerinin %66'sı yıllık (en yıllık-ağırlıklı
   kategori), deneme→ödeme %43,5, kategorinin %51,2'si ön izleme *ve* denemeyi
   **birlikte** kullanıyor — ön izleme denemenin alternatifi değil, aynı
   hunide üst üste iki adım (3. turdaki varsayım bu veriyle çürüdü).

### 9.1 Kanıtın sınırları — bu bir "kanıtlandı" değil

4. turdaki gerekçe **aboneliğin trip-pass'ten iyi olduğunu kanıtlamıyor:**

- **RevenueCat verisi seçim yanlılığı taşır.** Veri yalnızca abonelik
  kullanan uygulamalardan gelir; tek seferlik satanlar kümede yoktur.
  Dolayısıyla iki modeli karşılaştıramaz (§2.2 uyarısı).
- **%66 yıllık endojendir** — uygulamaların sattığını ölçer, kullanıcı
  tercihini paywall tasarımından ayrıştırmaz.
- **Rakiplerde trip-pass olmaması** modeli çürütmez; yalnızca ana model
  olarak seçmek için pazar kanıtı olmadığını gösterir.

**Doğru ifade:** "Abonelik kanıtlandı" değil — **"abonelik şu anda test
edilmesi en güçlü hipotez."**

### 9.2 Yeniden değerlendirme kapısı

İlk **100–200 nitelikli kullanıcının** satın alma ve kullanım verisi
toplandığında model yeniden değerlendirilir. Karar girdileri:

| Sinyal | Nereye işaret eder |
|---|---|
| Aylık payı yüksek, yıllık düşük | Kullanıcı tek-gezi aracı görüyor → **trip-pass / hibrit** yeniden masaya gelir |
| Yıllık payı yüksek, 2. ay tutunma iyi | Abonelik doğru → mevcut modelde derinleş |
| Deneme→ödeme düşük | Sorun fiyat değil ön izleme/değer anlatımı → önce onu düzelt, **fiyatı düşürme** |
| Gezi sırasında kullanım düşük | Ürün vaadi tutmuyor → özellik işi, fiyat işi değil |

Sezgiyle yeniden açmak yeterli değil — dört turun gösterdiği şey bu. Ama
**yukarıdaki sinyallerden biri gelirse açmak zorunlu.**

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
