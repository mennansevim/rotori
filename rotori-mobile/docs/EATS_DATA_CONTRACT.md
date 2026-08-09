# Rotori Eats — Veri Sözleşmesi (v1)

Toplayıcı uygulama ile Rotori arasındaki sözleşme. Toplayıcı **Katman A**'yı
üretir; **Katman B** Rotori'de elle kalır.

- **Hedef tablo:** Supabase `restaurants`
- **Teslim formatı:** NDJSON (satır başına bir JSON nesnesi) veya doğrudan
  Supabase upsert. Parquet de olur.
- **Kodlama:** UTF-8. Japonca alanlar ham kalır, romanize edilmez.
- **Anahtar:** `id` (bkz. §2)

---

## 0. Altın kural

> **Bilmediğin alanı `null` bırak. Asla tahmin etme.**

Rotori'nin skor motoru `null`'ı "eksik" olarak işler ve kullanıcıya öyle
gösterir. Uydurulmuş bir değer ise sessizce yanlış cevap üretir — bu, boş
bırakmaktan çok daha kötüdür. Özellikle `halal_trust` ve `price_*` alanlarında.

---

## 1. Katman A — senin uygulamanın üreteceği alanlar

### 1.1 Kimlik ve köken (ZORUNLU)

| Kolon | Tip | Zorunlu | Açıklama |
|---|---|---|---|
| `id` | text | ✅ | Kararlı birincil anahtar. Bkz. §2. |
| `source` | text | ✅ | `overture` \| `fsq` \| `osm` \| `curated` |
| `source_id` | text | ✅ | Kaynaktaki orijinal kimlik (Overture GERS id, FSQ id, OSM `node/123`) |
| `source_license` | text | ✅ | `CDLA-Permissive-2.0` \| `Apache-2.0` \| `ODbL-1.0` \| `proprietary-curated` |
| `source_ids` | jsonb | — | Aynı mekan birden çok kaynakta eşleştiyse: `{"osm":"node/123","fsq":"4b0..."}`. Dedup ve tazeleme için. |
| `first_seen_at` | date | ✅ | Bu kaydı ilk gördüğün tarih (YYYY-MM-DD) |
| `last_seen_at` | date | ✅ | Kaynağın bu kaydı **son teyit ettiği** tarih. Bayatlık ölçüsü budur. |

> `source_license` zorunlu çünkü ODbL kayıtlar için uygulamada atıf göstermek
> ve türev veritabanı yükümlülüğünü izlemek zorundayız. Lisansı bilinmeyen
> kayıt **alınmaz**.

### 1.2 Temel bilgi (ZORUNLU)

| Kolon | Tip | Zorunlu | Açıklama |
|---|---|---|---|
| `name` | text | ✅ | Latin harfli ad. Özel isim, çevrilmez. |
| `name_ja` | text | — | Japonca tabela adı. **Çok değerli** — kullanıcı sokakta mekanı bununla buluyor. Varsa mutlaka gönder. |
| `lat` | double | ✅ | WGS84. Japonya sınırı: 24.0–46.0 |
| `lng` | double | ✅ | WGS84. Japonya sınırı: 122.0–146.0 |
| `city` | text | ✅ | Tam olarak şunlardan biri: `Tokyo` \| `Kyoto` \| `Osaka` (v1 kapsamı) |
| `area` | text | ✅ | Semt/mahalle: `Shibuya`, `Gion`, `Namba`. Zincirlerde `Chain`. |
| `address` | text | — | Latin harfli tam adres |
| `address_ja` | text | — | Japonca adres — taksi şoförüne göstermek için |
| `postal_code` | text | — | `150-0002` biçimi |

### 1.3 Durum — bayatlık kontrolü (ZORUNLU)

| Kolon | Tip | Zorunlu | Açıklama |
|---|---|---|---|
| `status` | text | ✅ | `open` \| `closed` \| `unknown` |
| `closed_at` | date | — | `status = closed` ise biliniyorsa tarih |

> Bugünkü en büyük güvenilirlik açığı bu. FSQ OS Places'te kapanma sinyali
> var; Overture'da `confidence` alanı var. İkisini de kullan. `closed`
> kayıtları **silme**, gönder — Rotori listeden düşürür ama tekrar
> eklenmelerini engellemek için kaydı tutar.

### 1.4 Kategori ve fiyat

| Kolon | Tip | Zorunlu | Açıklama |
|---|---|---|---|
| `cuisine` | text | ✅ | §3.1'deki sözlükten TEK değer |
| `cuisine_raw` | text | — | Kaynaktaki ham kategori dizesi — eşleme hatalarını sonradan düzeltebilmek için sakla |
| `price_tier` | text | — | §3.3: `budget` \| `mid` \| `upper` \| `splurge` |
| `price_min_jpy` | int | — | Kişi başı alt sınır (JPY, vergi dahil) |
| `price_max_jpy` | int | — | Kişi başı üst sınır. `price_min_jpy <= price_max_jpy` |
| `rating` | double | — | 0.0–5.0, Google ölçeği |
| `rating_count` | int | — | Puanı kaç kişi verdi. **Bunsuz `rating` neredeyse değersiz** — 3 kişilik 5.0 ile 2000 kişilik 4.2 aynı şey değil. |
| `rating_source` | text | — | `google` \| `fsq` \| `osm` \| `tabelog` |
| `tabelog_score` | double | — | 1.0–5.0 Tabelog ölçeği. **Yalnızca gerçekten Tabelog'dan geldiyse.** Yoksa `null` — bu alanı asla Google puanıyla doldurma, iki ölçek farklı. |

### 1.5 Pratik alanlar

Hepsi `boolean` ve **üç durumlu**: `true` / `false` / `null` (bilinmiyor).
`false` ile `null` aynı şey değildir — `false` "yok olduğunu biliyoruz",
`null` "bilmiyoruz" demektir.

| Kolon | Tip | Açıklama |
|---|---|---|
| `card_ok` | bool | Kredi kartı geçiyor |
| `cash_only` | bool | Sadece nakit. **`card_ok` ile aynı anda `true` olamaz** |
| `english_menu` | bool | İngilizce menü var |
| `reservation_required` | bool | Rezervasyon zorunlu |
| `takeaway` | bool | Paket servis |
| `wheelchair_ok` | bool | Tekerlekli sandalye erişimi |
| `alcohol_served` | bool | Mekanda alkol servis ediliyor. **Helal katmanı için kritik** — sertifika tipini bu ayırıyor |
| `smoking_allowed` | bool | İç mekanda sigara |
| `opening_hours_raw` | text | OSM `opening_hours` sözdizimi (`Mo-Fr 11:00-14:30,17:00-22:00`). Ham gönder, Rotori parse eder. |
| `phone` | text | E.164: `+81312345678` |
| `website` | text | Mekanın kendi sitesi |
| `google_maps_url` | text | Derin bağlantı. **Places içeriği değil, sadece URL** — bu saklanabilir. |

### 1.6 Diyet — makine tarafı

| Kolon | Tip | Açıklama |
|---|---|---|
| `diet_halal_raw` | text | OSM `diet:halal` ham değeri: `yes` \| `only` \| `no` \| `limited` |
| `diet_vegan_raw` | text | OSM `diet:vegan` ham değeri |
| `diet_vegetarian_raw` | text | OSM `diet:vegetarian` ham değeri |
| `pork_free_claimed` | bool | Kaynak açıkça domuzsuz diyorsa |

> **Dikkat:** Bu alanlar `halal_trust` DEĞİLDİR. Ham sinyaldir. Rotori bunları
> okur ama kullanıcıya "helal" olarak göstermez — güven seviyesine
> yükseltmek Katman B'nin işi (§4). OSM'de bir kullanıcının `diet:halal=yes`
> yazması sertifika demek değildir.

---

## 2. `id` üretimi

Kararlı olmalı: aynı mekan her tazelemede aynı `id`'yi almalı, yoksa
kullanıcının kaydettikleri kopar.

```
{şehir kısaltması}-{kaynak}-{kaynak_id_slug}
örn:  tk-ovt-08f2a1b3c4d5e6f7
      ky-osm-node-123456789
      os-fsq-4b0588f3f964a520
```

Küratörlü kayıtlar (bizim mevcut 27) `curated` kaynak ekiyle korunur:
`tk-curated-gyumon`. Bunların `id`'lerini **değiştirme**.

**Dedup:** Aynı mekan birden çok kaynakta çıkarsa tek satır üret, kalan
kimlikleri `source_ids` içine koy. Eşleşme ölçütü önerisi: 75 m yarıçap +
normalize edilmiş ad benzerliği ≥ 0.85.

---

## 3. Sözlükler — birebir bu dizeler

Rotori bunları doğrudan enum'a çeviriyor; sözlük dışı değer **kaydı reddettirir**.

### 3.1 `cuisine`
```
ramen · sushi · yakiniku · curry · okonomiyaki · tempura · udon_soba
izakaya · kaiseki · burger · cafe · street_food · kushikatsu · world_food
```
Eşleyemediğin kategoriyi `world_food` yap ve ham değeri `cuisine_raw`'a koy.

### 3.2 `meal_slots` (text[])
```
breakfast · lunch · dinner · late_night
```
`opening_hours_raw` gönderirsen bunu Rotori türetir; sen de gönderebilirsin.

### 3.3 `price_tier` (kişi başı JPY)
```
budget   ≤ 1500
mid      ≤ 3500
upper    ≤ 7000
splurge  > 7000
```
`price_min_jpy`/`price_max_jpy` varsa `price_tier`'ı Rotori türetir; ikisi de
gelirse tutarlılık kontrol edilir.

---

## 4. Katman B — sen ÜRETME, Rotori'de kalır

Bunları göndermeni istemiyorum. Doğrulanmış kaynağın yoksa boş bırak.

| Kolon | Neden sende değil |
|---|---|
| `halal_trust` | `certified` \| `muslim_friendly` \| `pork_free_option` \| `none`. Japonya'da "Halal Restaurant" (alkolsüz) ile "Muslim-Friendly" (alkol var) **ayrı sertifikalar**. Bu ayrım belge görmeden yapılamaz. Sen `diet_halal_raw` + `alcohol_served` gönder, seviyeyi biz belirleriz. |
| `veggie_level` | Aynı mantık: Japon çorbalarında dashi gizli. `diet_vegan_raw` yeterli. |
| `description_tr` / `description_en` | Editoryal metin |
| `signature_tr` / `signature_en` | "Bunu söyle" — menü bilgisi + editoryal seçim |
| `insider_tip_tr` / `insider_tip_en` | Premium'un sattığı şey |
| `is_curated` | Rotori Seçkisi işareti |

**İstisna:** Elinde gerçekten sertifika kuruluşu belgesi varsa (JHA, NPO Japan
Halal Association vb.) şu iki alanı gönderebilirsin — o zaman biz yükseltiriz:

| Kolon | Tip | Açıklama |
|---|---|---|
| `halal_cert_body` | text | Sertifikayı veren kuruluşun adı |
| `halal_cert_source_url` | text | Belgenin/duyurunun URL'i |

---

## 5. Kabul kriterleri

Bir satır şu kontrollerden geçmezse alınmaz:

- [ ] `id`, `source`, `source_id`, `source_license`, `last_seen_at` dolu
- [ ] `name` boş değil, `lat`/`lng` Japonya sınırları içinde
- [ ] `city` ∈ {Tokyo, Kyoto, Osaka}
- [ ] `cuisine` sözlükte var
- [ ] `price_min_jpy <= price_max_jpy` (ikisi de doluysa)
- [ ] `rating` 0–5 aralığında ve `rating_count` dolu (biri varsa ikisi de)
- [ ] `card_ok` ve `cash_only` aynı anda `true` değil
- [ ] `status` sözlükte var
- [ ] Aynı `id` iki kez gelmiyor
- [ ] `tabelog_score` yalnızca `rating_source = tabelog` ise dolu

Rotori tarafında bu kurallar test olarak yazılacak; ihlal eden satır sessizce
düşmez, **hata verir**.

---

## 6. Örnek satır

```json
{
  "id": "tk-ovt-08f2a1b3c4d5e6f7",
  "source": "overture",
  "source_id": "08f2a1b3c4d5e6f7",
  "source_license": "CDLA-Permissive-2.0",
  "source_ids": { "osm": "node/1234567890" },
  "first_seen_at": "2026-08-10",
  "last_seen_at": "2026-08-10",

  "name": "Gyukatsu Motomura Shinjuku",
  "name_ja": "牛かつもと村 新宿店",
  "lat": 35.6906,
  "lng": 139.7004,
  "city": "Tokyo",
  "area": "Shinjuku",
  "address": "3-32-2 Shinjuku, Shinjuku City, Tokyo",
  "address_ja": "東京都新宿区新宿3-32-2",
  "postal_code": "160-0022",

  "status": "open",
  "closed_at": null,

  "cuisine": "tempura",
  "cuisine_raw": "tonkatsu_restaurant",
  "price_tier": "mid",
  "price_min_jpy": 1500,
  "price_max_jpy": 2500,
  "rating": 4.4,
  "rating_count": 3821,
  "rating_source": "google",
  "tabelog_score": null,

  "card_ok": false,
  "cash_only": true,
  "english_menu": true,
  "reservation_required": false,
  "takeaway": false,
  "wheelchair_ok": null,
  "alcohol_served": true,
  "smoking_allowed": false,
  "opening_hours_raw": "Mo-Su 11:00-22:00",
  "phone": "+81352962929",
  "website": null,
  "google_maps_url": "https://www.google.com/maps/search/?api=1&query=35.6906,139.7004",

  "diet_halal_raw": null,
  "diet_vegan_raw": null,
  "diet_vegetarian_raw": null,
  "pork_free_claimed": null,

  "halal_cert_body": null,
  "halal_cert_source_url": null
}
```

---

## 7. Öncelik — hepsini birden yapma

**Faz 1 (bunu istiyorum):** §1.1 + §1.2 + §1.3 + `cuisine`
→ Yani: kimlik, köken, ad, koordinat, şehir/semt, açık mı, mutfak türü.
Bu kadarıyla bile katalog 27'den binlere çıkar ve kapanmışlık riski çözülür.

**Faz 2:** fiyat + puan + `rating_count` + `opening_hours_raw`

**Faz 3:** pratik boolean'lar + diyet ham alanları + `name_ja`/`address_ja`

Faz 1'i teslim et, Rotori tarafını bağlayayım, sonra 2 ve 3'ü ekleriz.

---

## 8. Tazeleme

- **Sıklık:** ayda bir yeterli (FSQ OS Places zaten aylık yayınlıyor)
- **Yöntem:** tam snapshot gönder, Rotori `id` üzerinden upsert eder
- **Silme:** kaydı listeden çıkarma — `status = "closed"` işaretle. Kaybolan
  `id` "kapandı mı yoksa pipeline mı atladı" belirsizliği yaratır.
- **Değişiklik günlüğü:** mümkünse `last_seen_at` her turda güncellensin;
  Rotori "3 aydır teyit edilmedi" uyarısını buradan üretecek.

---

## 9. Kaynak notları

| Kaynak | Lisans | Nasıl alınır |
|---|---|---|
| **Overture Maps Places** | CDLA-Permissive-2.0 | S3/Azure'da açık Parquet, kayıt gerekmez. DuckDB ile bbox sorgusu. Share-alike yok. **Başlamak için en rahatı.** |
| **Foursquare OS Places** | Apache-2.0 | Places Portal'dan ücretsiz hesap + token; HuggingFace'te de var. Aylık güncel, kapanma sinyali iyi. |
| **OpenStreetMap** | ODbL-1.0 | Overpass API veya Geofabrik Japonya ekstresi. `diet:*`, `payment:*`, `opening_hours` için **en iyi kaynak**. Atıf zorunlu. |

**Google Places kullanma.** Şartları içeriğin cache'lenmesini/saklanmasını
yasaklıyor (`place_id` süresiz, koordinat 30 gün, gerisi hiç). Veritabanı
kurmak tanımı gereği ihlal; API anahtarı ve Cloud hesabı iptal riski var.
Maps web arayüzünü kazımak da ayrıca ihlal.

---

*v1 — 2026-08-10. Değişiklik önerisi için Rotori tarafına dön; şema
`lib/domain/eats.dart` ile birebir eşleşiyor.*
