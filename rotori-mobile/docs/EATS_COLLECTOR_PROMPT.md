# Rotori Eats veri toplayıcı — kurulum prompt'u

Aşağıdaki bloğu yeni ve boş bir depoda bir kodlama ajanına (Claude Code vb.)
olduğu gibi ver. `EATS_DATA_CONTRACT.md` dosyasını da o depoya kopyala.

---

## PROMPT — buradan aşağısını kopyala

Rotori adlı bir Japonya gezi uygulaması için **restoran verisi toplama job'ı**
yazacaksın. Bu bağımsız bir Python projesi; Rotori'nin mobil kodu burada yok.
Çıktın, mobil uygulamanın okuyacağı bir veri kümesi.

### Bağlam

Rotori kullanıcıya Japonya'da nerede yiyeceğini söylüyor: diyet kısıtı (helal,
vejetaryen, vegan), öğün bütçesi ve gezi planındaki konumuna göre. Bugün
elimizde **elle yazılmış 27 restoran** var — ürün olmaya yetmiyor. Senin
job'ın bunu **binlerce doğrulanabilir kayda** çıkaracak.

### MUTLAK KISIT — Google Places kullanma

Google Maps Platform şartları Places içeriğinin saklanmasını yasaklıyor:
`place_id` süresiz saklanabilir, koordinatlar en fazla 30 gün, **isim, adres,
puan, çalışma saati dahil geri kalan hiçbir şey saklanamaz.** Veritabanı
kurmak tanımı gereği ihlal; sonucu API anahtarının ve Google Cloud hesabının
iptali. Maps web arayüzünü kazımak da ayrıca ihlal ve teknik olarak engelli.

**Google Places API'ye ve Google Maps kazımasına hiç dokunma.** Bunu bir
alternatif olarak önerme, kod yolu olarak bile bırakma.

### Kaynaklar — bunları kullan

| Kaynak | Lisans | Erişim |
|---|---|---|
| **Overture Maps Places** | CDLA-Permissive-2.0 | S3'te açık Parquet, kayıt/anahtar gerekmez. Birincil kaynak. |
| **OpenStreetMap** | ODbL-1.0 | Overpass API veya Geofabrik Japonya ekstresi. `diet:*`, `payment:*`, `opening_hours`, `name:ja` için en iyi kaynak. |
| **Foursquare OS Places** | Apache-2.0 | Ücretsiz Places Portal token'ı ya da HuggingFace. Aylık güncel; kapanma sinyali güçlü. Opsiyonel, faz 2. |

Overture'ın güncel sürüm yolunu https://docs.overturemaps.org/release/
adresinden al — sürüm dizini her ay değişiyor, tarihi koda gömme, yapılandırma
yap ve varsayılanı "en son sürüm" olarak çöz.

Her kayıtta hangi kaynaktan geldiğini ve lisansını **taşımak zorundasın**;
ODbL kayıtlar için mobil uygulamada atıf göstereceğiz.

### Kapsam (v1)

- Şehirler: **Tokyo, Kyoto, Osaka**
- Kategoriler: restoran, kafe, fast food
- Hedef: şehir başına birkaç bin kayıt

### Çıktı sözleşmesi

Şema `EATS_DATA_CONTRACT.md` dosyasında — **önce onu oku, kolon adları ve
sözlükler birebir uyacak.** Sözlük dışı bir değer üretirsen kayıt reddedilir.

Kritik kurallar:

1. **Bilmediğin alanı `null` bırak. Asla tahmin etme.** Tüketici taraf `null`'ı
   "eksik" olarak gösteriyor; uydurulmuş değer sessizce yanlış cevap üretiyor.
2. Boolean alanlar **üç durumlu**: `true` / `false` / `null`. `false` "yok
   olduğunu biliyoruz", `null` "bilmiyoruz" demek. İkisini karıştırma.
3. **`halal_trust` ve `veggie_level` ÜRETME.** Japonya'da "Halal Restaurant"
   (alkolsüz) ile "Muslim-Friendly" (alkol servisi var) ayrı sertifikalar; bu
   ayrım belge görmeden yapılamaz. Sen yalnızca ham sinyali gönder:
   `diet_halal_raw`, `diet_vegan_raw`, `diet_vegetarian_raw`,
   `pork_free_claimed`, `alcohol_served`. Seviyeye yükseltmek tüketici tarafın
   işi.
4. **Editoryal metin üretme**: `description`, `signature`, `insider_tip`
   alanlarını doldurma, LLM'e yazdırma. Bunlar küratörlü katmana ait.
5. `tabelog_score` yalnızca gerçekten Tabelog kaynaklıysa dolsun. Google
   puanıyla doldurma — iki ölçek farklı (Japonya'da Tabelog 3.5 zaten üst
   seviye).
6. `rating` gönderiyorsan `rating_count` de gönder. Sayısı bilinmeyen puan
   neredeyse değersiz.

### Pipeline

**Aşama 1 — Çek.** Overture Places'i üç şehrin bbox'ıyla sorgula, kategoriye
göre filtrele. DuckDB + httpfs/spatial uzantılarıyla doğrudan S3 parquet'ten
okuyabilirsin; tüm gezegeni indirme.

**Aşama 2 — Zenginleştir.** Aynı bölgeler için OSM'den `diet:*`, `payment:*`,
`opening_hours`, `name:ja`, `addr:*`, `phone`, `website` çek. Overture
kayıtlarıyla eşleştir.

**Aşama 3 — Dedup + birleştir.** Aynı mekan birden çok kaynakta çıkabilir.
Eşleşme ölçütü: **75 m yarıçap + normalize edilmiş ad benzerliği ≥ 0.85**
(Japonca/Latin ad ayrı ayrı denenmeli; şube ekleri "新宿店" gibi normalize
edilmeli). Tek satır üret, kalan kimlikleri `source_ids` içine koy. Alan
çakışmasında öncelik: OSM (diyet/ödeme/saat) > Overture (ad/koordinat/kategori).

**Aşama 4 — Eşle.** Kaynak kategorilerini sözleşmedeki 14'lük `cuisine`
sözlüğüne eşle. Eşleşmeyeni `world_food` yap ve ham değeri `cuisine_raw`'da
sakla — eşleme tablosunu sonradan düzeltebilmemiz için bu şart.

**Aşama 5 — Doğrula.** Sözleşmedeki kabul kriterlerini uygula. **İhlal eden
satır sessizce düşmesin**: reddedilenleri sebebiyle birlikte ayrı bir dosyaya
yaz ve özet raporla.

**Aşama 6 — Yaz.** NDJSON (satır başına bir nesne) üret. Ayrıca `--supabase`
bayrağıyla doğrudan `restaurants` tablosuna `id` üzerinden upsert edebilsin.

### Kararlılık ve tazeleme

- `id` **kararlı** olmalı: aynı mekan her koşuda aynı `id`'yi almalı, yoksa
  kullanıcıların kaydettikleri kopar. Biçim: `{şehir}-{kaynak}-{kaynak_id}`,
  ör. `tk-ovt-08f2a1b3c4d5e6f7`.
- Job **idempotent** olmalı: iki kez çalıştırmak aynı sonucu versin.
- Aylık **tam snapshot** üret.
- **Kaydı asla listeden çıkarma** — kapananı `status: "closed"` işaretle.
  Kaybolan `id`, "kapandı mı yoksa pipeline mı atladı" belirsizliği yaratır.
- Önceki koşuyla diff çıkar: kaç yeni, kaç kapanmış, kaç alan değişmiş.

### Teknik beklentiler

- **Python 3.11+**, bağımlılıklar `pyproject.toml` ile
- **DuckDB** (parquet/S3/spatial) ve **httpx**; ağır ORM kullanma
- Konfigürasyon dosyayla (şehir bbox'ları, Overture sürümü, çıktı yolu) —
  sabit kodlama yok
- Ağ çağrılarında yeniden deneme + hız sınırlama; Overpass'a saygılı ol
  (paralel istek yok, timeout yüksek)
- Ara sonuçları lokal cache'le; her denemede baştan indirme
- Yapılandırılmış log: aşama başına giren/çıkan kayıt sayısı
- **Testler:** kategori eşleme, dedup eşleşmesi (pozitif ve negatif örnek),
  doğrulama kuralları, `id` kararlılığı. Ağ testleri sabit örneklerle
  (fixture), canlı istekle değil.
- `README.md`: nasıl çalıştırılır, hangi çıktı nereye gider, aylık koşu nasıl
  kurulur

### Kabul — bitti demek için

- [ ] `python -m collector run --cities tokyo,kyoto,osaka` çalışıyor
- [ ] Sözleşmeye uygun NDJSON üretiyor, kabul kriterlerinden geçiyor
- [ ] Reddedilen satırlar sebebiyle birlikte raporlanıyor
- [ ] İki kez çalıştırınca aynı `id` kümesi çıkıyor
- [ ] Her kayıtta `source`, `source_license`, `last_seen_at` dolu
- [ ] Hiçbir kayıtta `halal_trust`, `veggie_level` veya editoryal metin yok
- [ ] Testler geçiyor
- [ ] README kurulum ve aylık koşuyu anlatıyor
- [ ] Kod tabanında Google Places'e hiçbir referans yok

### Faz sırası — hepsini birden yapma

**Faz 1 (önce bunu bitir):** kimlik + köken + ad + koordinat + şehir/semt +
`status` + `cuisine`. Bu kadarıyla bile katalog binlere çıkar ve "kapanmış
restorana yönlendirme" riski çözülür.

**Faz 2:** fiyat + puan + `rating_count` + `opening_hours_raw` + FSQ kapanma
sinyali.

**Faz 3:** pratik boolean'lar + diyet ham alanları + `name_ja` / `address_ja`.

Faz 1'i teslim edip **gerçek sayıları raporla** — şehir başına kaç kayıt,
hangi alanlar ne oranda dolu, kaç kayıt reddedildi ve neden. Faz 2'ye
geçmeden önce bu rapora bakacağız.

### Başlarken

Önce `EATS_DATA_CONTRACT.md`'yi oku. Sonra kod yazmadan **küçük bir keşif
adımı** yap: Overture'dan yalnızca Tokyo bbox'ını çekip kaç restoran kaydı
geldiğini, hangi alanların dolu olduğunu ölç ve raporla. Veri beklediğimiz
gibi değilse pipeline'ı ona göre kurarız.

## PROMPT — buraya kadar
