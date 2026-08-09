# Rotori Eats — Veri Güvenilirliği QA Checklist

> **Kapsam:** `lib/domain/eats.dart` içindeki 27 küratörlü restoran kaydı.
> **Amaç:** Kullanıcıya para ödettiğimiz bir özelliğin verisinin doğru
> olduğunu kanıtlamak — özellikle helal iddialarının.

---

## 0. Önce şunu bil: veri CANLI DEĞİL

Bu, checklist'in var olma sebebi. Yanlış varsayım büyük hataya yol açar.

| Soru | Cevap |
|---|---|
| Google Places API'den mi çekiliyor? | **Hayır.** Hiçbir API çağrısı yok. |
| Herhangi bir canlı kaynaktan çekiliyor mu? | **Hayır.** `eats.dart` içinde sabit kodlanmış 27 kayıt. |
| Ağ isteği yapıyor mu? | **Hayır.** Tek dış temas: kullanıcı "Haritada aç"a bastığında Google Maps uygulamasını açmak (`openGoogleMapsPoint`). Veri okumaz, sadece uygulama başlatır. |
| Puanlar Google'dan mı? | **Hayır.** Elle girilmiş, "Google ölçeğine yakın" yaklaşık değerler. |
| Tabelog puanı var mı? | **Yok.** `tabelogScore` alanı modelde tanımlı ama **27 kaydın 27'sinde de null** — doğrulanmamış puan uydurulmadı. |
| Koordinatlar ölçülmüş mü? | **Hayır.** Elle girilmiş yaklaşık değerler. |
| `verifiedOn: '2026-07'` ne demek? | Yalnızca **derleme ayı**. Mekan aranmadı, sertifika belgesi görülmedi, hiçbir teyit alınmadı. |

**Sonuç:** Bu bir veritabanı değil, bir *editoryal seçki*. Güvenilirliği
otomatik testle değil, **insan doğrulamasıyla** kanıtlanır. Aşağısı onun planı.

### Veri profili (mevcut durum)

| Kırılım | Sayı |
|---|---|
| Toplam mekan | 27 |
| `premiumOnly` (Rotori Seçkisi) | 3 |
| Şehir dağılımı | Tokyo 14 · Kyoto 7 · Osaka 6 |
| `HalalTrust.certified` | 5 |
| `HalalTrust.muslimFriendly` | 3 |
| `HalalTrust.porkFreeOption` | 7 |
| `HalalTrust.none` | 12 |
| `insiderTip` dolu | 17 |

---

## 1. P0 — Helal iddiaları (yayın engelleyici)

Bu bölümün tamamı geçmeden **Eats Pass satılmamalı**. Yanlış bir helal
rozeti, kullanıcının dinî olarak yiyemeyeceği bir şeyi yemesine yol açar;
bu, "puan biraz yanlıştı"dan kategorik olarak farklı bir hatadır.

### 1.1 `certified` işaretli 5 kayıt — her biri tek tek

| # | id | Mekan | Konum |
|---|---|---|---|
| ☐ | `tk-gyumon` | Gyumon | Tokyo / Shibuya |
| ☐ | `tk-naritaya` | Naritaya | Tokyo / Asakusa |
| ☐ | `tk-honolu-ebisu` | Honolu Halal Ramen | Tokyo / Ebisu |
| ☐ | `tk-ayamya` | Ayam-Ya | Tokyo / Okachimachi |
| ☐ | `ky-naritaya-gion` | Naritaya Kyoto | Kyoto / Gion |

Her kayıt için:

- [ ] Mekan **hâlâ açık mı?** (Google Maps "kalıcı olarak kapandı" etiketi yok)
- [ ] Sertifikayı veren kuruluş **adıyla** belgelenebiliyor mu?
      (NPO Japan Halal Association, JHA, Muslim Professional Japan Assoc. vb.)
- [ ] Sertifika **hangi tip?** Japonya'da ayrım kritik:
      - *Halal Restaurant* = tamamen helal, **alkol yok**
      - *Muslim-Friendly Restaurant* = yemek helal ama **alkol servisi var**
      → Alkol servisi varsa kayıt `certified` DEĞİL, `muslimFriendly` olmalı.
- [ ] Mekanın kendi sitesi / resmî sosyal hesabı iddiayı doğruluyor mu?
- [ ] `amenities` içindeki `alcoholFree` bayrağı sertifika tipiyle tutarlı mı?
- [ ] En az **iki bağımsız kaynak** var mı? (tek blog yazısı yeterli değil)

**Kabul kriteri:** İki bağımsız kaynak + sertifika tipi netliği. Şüphe varsa
**bir alt seviyeye indir** (`certified` → `muslimFriendly` → `porkFreeOption`).
Şüpheyi kullanıcı değil, biz üstleniriz.

### 1.2 `muslimFriendly` işaretli 3 kayıt

`tk-sekai-cafe` · `tk-wagyu-halal-vegan` · `os-matsuri-halal`

- [ ] Domuz kullanılmadığı doğrulanabiliyor mu?
- [ ] Mirin / pişirme sakesi kullanımı biliniyor mu? (Bilinmiyorsa
      `explainer` metni bunu zaten söylüyor — metnin doğru olduğunu teyit et.)
- [ ] `prayerSpace` bayrağı işaretliyse namaz alanı gerçekten var mı?

### 1.3 Ters yön kontrolü — yanlış negatif

- [ ] `HalalTrust.none` işaretli 12 kayıt arasında aslında helal/domuzsuz
      seçeneği olan var mı? (Yanlış negatif kullanıcıya zarar vermez ama
      ürünü zayıflatır.)
- [ ] `os-ichiran-dotonbori` gibi domuz suyu bazlı mekanların `insiderTip`
      metninde uyarı duruyor mu?

---

## 2. P0 — Mekan var mı, doğru yerde mi

Kapanmış bir restorana yönlendirmek, premium bir üründe kabul edilemez.

Her 27 kayıt için:

- [ ] **Varlık:** Google Maps'te arandığında bulunuyor, "kalıcı olarak
      kapandı" yazmıyor.
- [ ] **Koordinat:** `lat`/`lng` mekanın gerçek konumuna **150 m** içinde.
      *Nasıl:* `https://www.google.com/maps/search/?api=1&query=LAT,LNG`
      açıp pinin mekanın üstüne düştüğünü gör.
- [ ] **Şehir/semt:** `city` ve `area` alanları doğru.
- [ ] **Japonca ad (`nameJa`):** Tabeladaki adla eşleşiyor. Bu alan kullanıcının
      sokakta mekanı bulma yolu — yanlışsa işe yaramaz.
- [ ] **Zincir tuzağı:** `tk-coco-ichibanya` gibi zincirlerde koordinat *bir*
      şubeye ait. `area: 'Zincir / Chain'` etiketi bunu söylüyor mu?

---

## 3. P1 — Fiyat, puan, olanaklar

- [ ] `priceMinJpy` / `priceMaxJpy` güncel menüyle uyumlu (±%25 tolerans).
      Japonya'da 2024–2026 arası belirgin zam oldu; eski blog fiyatları düşük.
- [ ] `priceTier` fiyat aralığıyla tutarlı
      (`budget ≤1500 · mid ≤3500 · upper ≤7000 · splurge >7000`).
- [ ] `rating` Google'daki güncel puandan **±0.3** içinde.
- [ ] `cardOk` işaretliyse gerçekten kart geçiyor; `cashOnly` işaretliyse
      gerçekten sadece nakit. **Bu ikisi aynı anda işaretli olamaz**
      (otomatik test bunu zaten koruyor: `eats_query_test.dart`).
- [ ] `englishMenu` iddiası doğru mu? (Turist için en çok kullanılan filtre.)
- [ ] `queueLikely` / `reservationRecommended` hâlâ geçerli mi?
- [ ] `slots` (kahvaltı/öğle/akşam/gece) kabaca doğru mu? UI bunu "tahmini"
      diye etiketliyor ama tamamen yanlış olmamalı.

---

## 4. P1 — İçerik kalitesi

- [ ] `signature` (imza yemek) mekanın menüsünde **gerçekten var**.
- [ ] `insiderTip` (17 kayıtta dolu) doğrulanabilir bir bilgi mi, yoksa genel
      geçer laf mı? Premium'un satılan değeri bu — "kuyruk 40 dk'yı bulur"
      gibi bir iddia kaynaklanabilmeli.
- [ ] `description` metninde abartı/uydurma yok.
- [ ] Türkçe ve İngilizce metinler **aynı şeyi** söylüyor (LText çiftleri).
- [ ] Japonca sipariş frazları dilbilgisi olarak doğru — anadili konuşan
      biri gözden geçirdi mi? (`eats_detail_sheet.dart` → `_phrasesFor`)

---

## 5. P2 — Skorun dürüstlüğü

Skorun kendisi hesaplama; testleri otomatik. Buradaki kontrol **sunum**:

- [ ] Diyet + bütçe girilmemişken büyük sayı **gösterilmiyor**
      ("Henüz kişiselleştirilemiyor" çıkıyor).
- [ ] Eksik sinyaller "eksik" olarak, doldurma çağrısıyla listeleniyor.
- [ ] Kısmi durumda "N/4 sinyal" rozeti doğru sayıyı gösteriyor.
- [ ] Konum kapalıyken mesafe bileşeni **eksik**, sıfır değil.
- [ ] Ana ekrandaki "Öneriler henüz sana göre değil" kartı, girdiler
      dolunca kayboluyor.

*Otomatik kapsam:* `test/domain/eats_query_test.dart`,
`test/features/viewer/eats_personalization_test.dart`

---

## 6. P2 — Katman sınırı (ücretsiz / Pass)

- [ ] Ücretsiz katmanda arama başına en fazla `kEatsFreeVisibleLimit` (6)
      sonuç, ve kaç sonucun gizlendiği **açıkça yazılı**.
- [ ] `premiumOnly` 3 kayıt ücretsizde hiç görünmüyor.
- [ ] Premium filtre eksenleri ücretsizde **uygulanmıyor** (kilitli görünüp
      arkada sessizce çalışmıyor).
- [ ] **Güvenlik bilgisi hiçbir katmanda kilitli değil:** helal seviye
      açıklaması, nakit uyarısı, sipariş frazları, harita.

*Otomatik kapsam:* `test/features/viewer/eats_screen_test.dart`

---

## 7. Tekrar sıklığı ve sahiplik

| Ne | Ne sıklıkla | Neden |
|---|---|---|
| Helal iddiaları (Bölüm 1) | **3 ayda bir** + her sürüm öncesi | Sertifika iptal edilebilir |
| Mekan varlığı (Bölüm 2) | 6 ayda bir | Japonya'da küçük mekanlar hızlı kapanır |
| Fiyat / puan (Bölüm 3) | 6 ayda bir | Enflasyon kayması |
| İçerik (Bölüm 4) | Yeni kayıt eklendikçe | — |
| Skor + katman (5–6) | Her sürümde (otomatik) | CI zaten koşuyor |

Her turdan sonra ilgili kayıtların `verifiedOn` alanını güncelle **ve** bu
dosyanın altına tarih + kim baktı notu düş.

---

## 8. Ölçeklenince: bu checklist yetmez

27 kayıt elle doğrulanabilir. 200 kayıtta bu model çöker. O noktada
seçenekler:

1. **Supabase `restaurants` tablosu** — `eats.dart` zaten aynı alan adlarıyla
   bu göçe hazır tasarlandı. Doğrulama iş akışı (kim, ne zaman, hangi kaynak)
   veriyle birlikte tutulur.
2. **Google Places API** — canlı varlık/saat/puan verir ama helal ve pratik
   alanları (nakit-only, mirin kullanımı, namaz alanı) **vermez**; küratörlü
   katman yine gerekir. Ayrıca maliyet ve çevrimdışı çalışma kaybı.
3. **Hibrit (önerilen):** varlık + saat + puan Places'ten, güven seviyeleri ve
   pratik alanlar küratörlü kalır.

Şu anki mimari 3'e uygun: `EatsPlace.tabelogScore` gibi alanlar boş bırakıldı
ve model canlı veriyle doldurulmayı bekliyor.

---

## Doğrulama günlüğü

| Tarih | Bölüm | Bakan | Sonuç |
|---|---|---|---|
| — | — | — | *(ilk tur henüz yapılmadı)* |
