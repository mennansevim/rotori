# GROWTH_SEO_STRATEGY.md — Rotori Dağıtım ve SEO Stratejisi

> Rotori'nin kullanıcı edinme stratejisi. Monetizasyon modeli için
> `MONETIZATION_PLAN.md`; bu belge **hacim** tarafını ele alır.
>
> **Oluşturulma:** 2026-08-10
>
> **Neden ayrı belge:** Gelirin belirleyicisi fiyat değil dağıtım
> (`MONETIZATION_PLAN.md` §1). Dağıtımın kendi yürütme mantığı, kendi
> zaman ufku ve kendi riskleri var — monetizasyon planının alt maddesi
> olarak taşınamaz.

---

## 1. Neden bu belge var

`MONETIZATION_PLAN.md` §2.2'deki kategori verisi:

- İndirme→ödeme dönüşümü medyanı **%2,0**
- $1K aylık gelire ulaşma süresi medyan **238 gün**
- Yeni seyahat uygulamalarının yalnızca **%9,8'i** 2 yılda $10K MRR'a ulaşıyor

Bu ortamda fiyat optimizasyonunun getirisi sınırlı; **hacim** belirleyici.
1.000 indirme → ~20 ödeyen. Anlamlı gelir için indirmenin on binler
mertebesine çıkması gerekiyor.

## 2. Kanıt: Wanderlog nasıl büyüdü

Kategorinin en yakın karşılaştırılabilir oyuncusu **3,6–5 milyon indirmeye**
reklamla değil, **içerikle ve SEO ile** çıktı:

- Kullanıcı itinerary'lerini herkese açık ve indekslenebilir hale getirdi
- Organik web trafiğinin **%60'ından fazlası** long-tail aramalardan geliyor
  ("7 günlük Tokyo rotası" tipi sorgular)
- Üstüne AI kişiselleştirme ile e-posta nudge'ları koydu (CTR +%22)
- 4.9 mağaza puanını korurken global ölçeğe çıktı

**Rotori için çıkarım:** Video kanalı (@japonyaruyasi) hızlı ama **eriyen**
bir varlık — bir reels 48 saatte ölür. İndekslenmiş bir sayfa **birikimli**:
yıllarca trafik getirir. İkisi birbirinin alternatifi değil; video kısa
vadeli ivme, SEO uzun vadeli taban.

## 3. Kanal 1 — Video hattı (kısa vadeli ivme)

Altyapı kurulu: ~1000 videoluk Japonya arşivi, otomatik reels üretimi,
TikTok cross-post, analytics. Kanal yayında (10–15 video) ama gönderiler
elle yapılıyor; otomasyon hattı bugüne dek 2 gönderi üretmiş.

- [ ] `rotori-social/data/automation_config.json` → `topic.enabled: false`
      **açılır** (şu an kapalı; bilinçli mi kapatıldığı doğrulanmalı)
- [ ] TikTok cross-post devreye alınır (`tiktok_publisher.py` hazır,
      `data/tiktok_uploads.jsonl` henüz oluşmamış)
- [ ] Haftada 3 gönderi sürekliliği

### 3.1 Hook stratejisi — problem odaklı, özellik demosu değil

Özellik demosu ("AR overlay şöyle çalışıyor") zayıf dönüşür. Problem odaklı
hook, kullanıcının kafasındaki soruyla eşleşir:

- "Tokyo'da aynı güne koymamanız gereken 3 yer"
- "Japonya seyahatinde yapılan en pahalı ulaşım hatası"
- "JR Pass gerçekten gerekli mi?"
- "10 günlük Japonya rotası nasıl bölünür?"
- "Japonya'da rezervasyonu önceden yapılması gereken yerler"
- "ChatGPT'nin Japonya planlarında yaptığı 5 hata"

Hepsi tek CTA ile biter: **"Ücretsiz Japonya rota ön izlemeni oluştur."**

Avantaj: bu içeriklerin cevabı **Rotori'nin kendi verisinde** var —
`domain/city_places.dart`, `assets/data/unit_costs.ini`, optimizer kuralları.
Uydurma içerik üretmeye gerek yok.

### 3.2 EN kuyruğu

l10n %100 iki dilli (1240/1240). Global Japonya pazarı ~10 kat büyük ve
abonelik ekonomisi USD fiyatlarında daha sağlıklı. TR ve EN **ayrı içerik
kuyruğu** olarak yürütülür — çeviri değil, ayrı hook seti.

## 4. Kanal 2 — SEO motoru (uzun vadeli taban)

### 4.1 Yapmayacağımız şey: tüm kullanıcı planlarını otomatik yayımlamak

Wanderlog'un modeli bu, ama doğrudan kopyalanamaz. Üç sorun:

1. **Gizlilik.** Plan verisi tarih, otel adı, uçuş bilgisi ve kişisel not
   içeriyor. Bunları rıza olmadan yayımlamak kabul edilemez.
2. **İnce ve kopya içerik.** Birbirinin neredeyse aynısı yüzlerce
   otomatik sayfa, Google'ın doorway/duplicate içerik değerlendirmesine
   girer — trafik getirmek yerine domain'i zayıflatır.
3. **Kalite kontrolü yok.** Yarım bırakılmış, test amaçlı ya da anlamsız
   planlar indekslenir.

### 4.2 Aşama 1 — Editoryal olarak doğrulanmış 20–30 rota

- [ ] Elle küratörlü, benzersiz ve gerçekten faydalı 20–30 rota üretilir
- [ ] Her biri kendi indekslenebilir sayfası olur:
  - 7 günlük Tokyo rotası
  - 10 günlük Tokyo–Kyoto–Osaka rotası
  - Çocuklu aile için Japonya rotası
  - Anime odaklı Japonya rotası
  - 14 günlük Japonya bütçesi
  - İlk kez Japonya: 5 günlük minimum rota
  - Sakura sezonu rotası
- [ ] Her sayfa **benzersiz** içerik taşır: neden bu sıra, hangi durak
      hangi güne, tahmini bütçe, ulaşım notları
- [ ] Her sayfadan **kişiselleştirilmiş plan oluşturmaya** geçiş CTA'sı
- [ ] Hedef sorgular: "Tokyo Kyoto Osaka kaç gün", "Japonya 10 günlük rota",
      "Japonya 2 hafta bütçe", "Japonya ilk kez nereden başlanır"

### 4.3 Aşama 2 — Açık rıza ile kullanıcı planı yayımlama

- [ ] Kullanıcıya **açık rıza** ile "planımı herkese açık yayımla" seçeneği
- [ ] Yayımlanan planda kişisel alanlar (otel adı, uçuş, notlar) **varsayılan
      olarak gizli**; kullanıcı tek tek açar
- [ ] Editoryal eşik: minimum gün/durak sayısı, tamamlanmışlık kontrolü
- [ ] `noindex` varsayılan, kalite eşiğini geçen sayfalar indekslenir

### 4.4 Teknik yaklaşım

**Legacy planner'ı olduğu gibi canlandırmak yanlış olur.**
`rotori-website/legacy/apps/planner/` bakım modunda, mobil öncesi nesil bir
React uygulaması ve mevcut plan modelinden farklı.

Doğru yol: **mevcut Rotori plan modelinden statik SEO sayfası üreten temiz
bir yayın hattı.**

- [ ] Plan modeli → statik HTML üreten generator (mobil ile aynı domain
      modelini okur, `domain/types.dart` ile uyumlu bir şema)
- [ ] Statik çıktı mevcut Pi + Docker hattından servis edilir (yeni altyapı
      gerekmez)
- [ ] Ön koşul: **plan veri modeli dışa aktarılabilir tutulur.** Faz 3'te
      ön izleme hunisi yazılırken plan çıktısının serileştirilebilir kalmasına
      dikkat edilir (`MONETIZATION_PLAN.md` §6.2 bağlantısı)

## 5. Kanal 3 — Affiliate katmanı (ikincil gelir)

Wanderlog aboneliğin yanında otel/uçuş komisyonu da alıyor. Indie seyahat
uygulamaları için en pratik ilk gelir kalemi; build maliyeti neredeyse sıfır.

- [ ] eSIM — her Japonya gezgini alıyor, komisyonlar %15–20 bandında
- [ ] JR Pass / bölgesel demiryolu pasları
- [ ] Otel rezervasyonu
- [ ] Yerleştirme: checklist, "Mutlaka Bilmeniz Gerekenler", kalkış öncesi
      hatırlatmalar
- [ ] **Talep oluştuktan sonra** eklenir — sıfır kullanıcıya affiliate linki
      koymak gelir üretmez

**Not:** Kısa vadede nakit hedefi varsa affiliate, abonelikten daha hızlı
getirir (`MONETIZATION_PLAN.md` §7).

## 6. Sıralama

Monetizasyon fazlarıyla paralel yürür:

| Sıra | İş | Ne zaman |
|---|---|---|
| 1 | Video otomasyonunu aç (`topic.enabled`) | **Hemen** — kod gerektirmez, Faz 1 ile paralel |
| 2 | Haftada 3 problem odaklı video | Sürekli |
| 3 | İlk 20–30 editoryal SEO rotası | Yayından sonra |
| 4 | SEO yayın hattı (plan modeli → statik sayfa) | Editoryal rotalar işe yararsa |
| 5 | Açık rıza ile kullanıcı planı yayımlama | SEO hattı oturduktan sonra |
| 6 | Affiliate katmanı | Talep oluştuğunda |

## 7. Ölçüm

| Metrik | Neden |
|---|---|
| Video → profil → mağaza tıklama zinciri | Video kanalının gerçek verimi |
| İndekslenen sayfa sayısı | SEO hattının ilerlemesi |
| Organik oturum / sayfa | Hangi rota sayfaları çalışıyor |
| SEO sayfası → plan oluşturma dönüşümü | SEO'nun ürüne bağlanması |
| Kanal başına indirme atfı | Bütçe/emek nereye gitmeli |

Dağıtım metrikleri ile huni metrikleri ayrı tutulur: bu belge **trafiği**,
`MONETIZATION_PLAN.md` §7 **trafiğin paraya dönüşmesini** ölçer.

## 8. Riskler

| Risk | Etki | Azaltma |
|---|---|---|
| Otomatik plan yayımlama gizlilik ihlali yaratır | Kritik | §4.1 — otomatik yayımlama yapılmaz; §4.3 açık rıza + varsayılan gizli alanlar |
| İnce/kopya içerik domain'i zayıflatır | Yüksek | Editoryal 20–30 sayfa ile başla; kalite eşiği + `noindex` varsayılan |
| Video hattı süreklilik kaybeder | Yüksek | Otomasyon zaten kurulu; haftada 3 hedefi ölçülür |
| SEO getirisi geç gelir (6–12 ay) | Orta | Beklenti baştan bu; video kısa vadeli ivmeyi taşır |
| Legacy planner'a gömülmek | Orta | §4.4 — canlandırma değil, yeni temiz generator |
| EN içeriğin TR kuyruğunu seyreltmesi | Orta | Ayrı kuyruk, ayrı hook seti |

---

## Kaynaklar

- [Wanderlog büyüme/pazarlama stratejisi](https://businessmodelcanvastemplate.com/blogs/marketing-strategy/wanderlog-marketing-strategy)
- [Wanderlog — App Store](https://apps.apple.com/us/app/wanderlog-travel-planner/id1476732439)
- [RevenueCat — State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps)
- [Indie seyahat uygulamaları gelir modelleri](https://www.anything.com/blog/travel-app-ideas)
