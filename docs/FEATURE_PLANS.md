# FEATURE_PLANS.md — Rotori Özellik Fikir Havuzu

> **Canlı backlog.** Özellik fikirleri burada toplanır; zamanla eklenir.
> Bu belge *fikir havuzudur* — taahhüt edilmiş yayın kapsamı değil.
>
> **Sınır:** Yayına alınmaya **karar verilmiş** özellikler ve fazlar
> `MONETIZATION_PLAN.md` (§3.2 Pro listesi, §4 kapsam, §5 fazlar) ile
> `CURRENT_TASK.md`'de yaşar. Bir fikir "yapılacak" olduğunda oraya taşınır,
> burada `→ MONETIZATION_PLAN` diye işaretlenir. Teknik sözleşme gerekiyorsa
> `ARCHITECTURE.md`.
>
> **Oluşturulma:** 2026-08-10

---

## Nasıl kullanılır

- Yeni fikir → uygun bölüme bir alt başlık ekle, aşağıdaki **şablonu** doldur.
- Bir fikir yayına alınacaksa: `MONETIZATION_PLAN.md`/`CURRENT_TASK.md`'ye taşı,
  buradaki kaydı **`→ taşındı`** durumuna çek (silme — fikrin gerekçesi kalsın).
- Reddedilen fikir **silinmez**; §5'e gerekçesiyle taşınır (aynı fikir bir
  sonraki oturumda yeniden önerilmesin).

### Fikir şablonu

```
### <Başlık>
- **Ne:** tek cümle
- **Neden / kanıt:** pazar verisi veya kullanıcı gerekçesi
- **Mevcut kod:** hangi dosya/altyapı zaten var (yoksa "yok — sıfırdan")
- **Maliyet:** COGS var mı (ücretli API?) + kaba efor
- **Katman:** Pro | Ücretsiz | Belirsiz
- **Durum:** fikir | araştırılıyor | → taşındı | reddedildi
```

### Durum etiketleri

`fikir` · `araştırılıyor` · `→ MONETIZATION_PLAN` (yayına alındı) ·
`reddedildi` (gerekçe §5'te)

---

## 0. Stratejik çerçeve — yeni fikir eklerken buna uy

Pazar araştırmasından (2026-08-10) çıkan üç ilke. Yeni özellik fikri bunlara
göre elenir:

1. **AI itinerary üretimi ücretsizleşti** (Mindtrip, Wonderplan paywall'sız).
   Rotori "AI sana plan yapsın"ı **satamaz**. Satış argümanı asla "akıllı
   planlama" olmaz.
2. **Ödenen değer iki yerde:** (a) gezi-anı gerçek-zamanlı fayda (TripIt'in tüm
   modeli), (b) offline/bağlantısızlık bağımsızlığı. İkisi de Rotori'nin
   yapısal gücü.
3. **Rotori'nin ayrışması:** Türkçe + Japonya-derinliği + offline + tarayıcılar
   + diyet/helal. Hiçbir rakipte bu dörtlü yok. Premium özellikler bunu
   **güçlendirmeli**, jenerik "seyahat asistanı" özelliklerini kovalamamalı.

Rakip paywall haritası (referans):

| Uygulama | Fiyat | Paywall'daki çekirdek |
|---|---|---|
| Wanderlog Pro | $39.99/yıl | Rota optimizasyonu, offline harita, Maps'e aktar, canlı uçuş |
| TripIt Pro | $49/yıl | Canlı uçuş uyarısı, fare tracker, koltuk takibi, havaalanı haritası, "Go Now" |
| Layla | $49/yıl | Gün-gün detay, PDF, sınırsız gezi |
| Mindtrip / Wonderplan | Ücretsiz | Çekirdek AI planlama (paywall yok) |
| NAVITIME Japan | ~¥330/ay | Tren navigasyonu: peron, aktarma, Shinkansen, JR Pass kapsamı |

---

## 1. Premium aday özellikler (öncelik sırasına göre)

### JR Pass / ulaşım pası karar motoru — "JR Pass sana değer mi?"
- **Ne:** Kullanıcının kendi rotasına göre "JR Pass mı, tek tek bilet mi?"
  hesabı; tavsiye + tasarruf miktarı.
- **Neden / kanıt:** JR Pass Ekim 2023 zammı sonrası artık her zaman kazançlı
  değil; SmartEX tek biletler çoğu kısa rotada daha ucuz (JRailPass/jrpass.com,
  2026). Japonya'ya gidenin kafaya taktığı, büyük ön-ödemeli (~₺8–15bin) karar.
  **Kimse kişiselleştirilmiş çözmüyor.** Türk gezgin için doğrudan para.
- **Mevcut kod:** Ham madde **var** — rota (şehir/gün), `cost_estimate.dart`,
  `assets/data/unit_costs.ini`, `0006_exchange_rates.sql`. Yeni: pas fiyat
  tablosu + karşılaştırma mantığı + sonuç kartı.
- **Maliyet:** Near-zero COGS (yerel hesap). Efor: orta (1–2 gün).
- **Katman:** Pro. Tek başına abonelik gerekçesi olabilir.
- **Durum:** fikir — **en güçlü aday**, MONETIZATION_PLAN'e alınması öneriliyor.

### Offline "tüm gezi" paketi
- **Ne:** Gitmeden tüm günlerin haritası + plan + ifadeler + rehber tek
  dokunuşla indirilir; Japonya'da internet olmadan çalışır.
- **Neden / kanıt:** Offline, araştırmadaki her listede en yüksek WTP'li
  kalem. Japonya'da hiçbir tren uygulaması iyi offline çalışmıyor (JRailPass
  2026). Roaming pahalı, gerçek bir korku.
- **Mevcut kod:** `prewarmTiles()` (`offline_tile_provider.dart:133`) yazılı
  ama tek gün + 400 tile üst sınır. Çok-günlü parçalı indirmeye genişlet.
- **Maliyet:** Near-zero COGS. Efor: 2–3 gün.
- **Katman:** Pro (ücretsiz kullanıcı yine görüntülediği günü cache'ler).
- **Durum:** → **MONETIZATION_PLAN Faz 3.4'te** (yayın sonrası).

### Kur + fiyat tarayıcı premium (AR overlay)
- **Ne:** Canlı kur tarayıcı + TR pazar fiyat karşılaştırması; kamerada yen
  fiyatının üstüne TL yazan AR overlay.
- **Neden / kanıt:** Kur/çeviri araştırmada en çok ödenen kalemlerden. AR
  overlay **hiçbir rakipte yok** ve Türkiye'ye özel.
- **Mevcut kod:** Büyük ölçüde **hazır** — `price_tag_scanner/`,
  `live_currency_scanner/`, 10/100 kota (`0008_daily_scans.sql`), AR overlay.
- **Maliyet:** Tarama başına ≈ ₺0.02 (gpt-4o-mini) — ihmal edilebilir.
- **Katman:** Pro (100/gün + pazar karşılaştırması); ücretsiz 10/gün.
- **Durum:** → **MONETIZATION_PLAN'de** (kota altyapısı mevcut).

### Rota optimizasyonu + "kazandırdığı saat"
- **Ne:** Günlük durakları yeniden sıralayıp ulaşım süresini kısaltma; "bu plan
  sana 6 sa 40 dk kazandırıyor" değer göstergesi.
- **Neden / kanıt:** Wanderlog Pro'nun çekirdek paywall özelliği. Değer somut
  ve ölçülebilir.
- **Mevcut kod:** Motor **var** (`BeamSearchItineraryOptimizer`,
  `totalTravelMinutes` öncesi/sonrası `plan_optimization_controller.dart:44`).
  **Dürüstlük şartı:** fallback yolundan gelen sonuçta kazanç sayısı gösterilmez
  (matris güvenilir değil) — bkz. DECISIONS 2026-08-10(b).
- **Maliyet:** Near-zero (yerel deterministik). AI POI keşfi Edge Function'da,
  orada `is_premium()` korunur.
- **Katman:** Pro (ücretsiz kullanıcıya 1 önizleme denemesi).
- **Durum:** → **MONETIZATION_PLAN Faz 3.1–3.2'de**.

### Uçuş durumu / canlı takip + "ne zaman çıkmalısın" (Go Now)
- **Ne:** Canlı uçuş durumu (rötar, kapı), kalkışa ne zaman çıkılmalı bildirimi.
- **Neden / kanıt:** TripIt Pro'nun tüm modeli bu; Flighty tarzı en kanıtlı
  seyahat paywall'ı. Rotori'de **eksik** (bilet hatırlatması var, canlı takip yok).
- **Mevcut kod:** Bilet OCR + `flutter_local_notifications` + `reminders/` var;
  canlı veri katmanı yok.
- **Maliyet:** ⚠ **Gerçek COGS** — ücretli uçuş-veri API'si gerekir. Diğer
  önerilerin aksine marjı düşürür. Efor: orta-yüksek.
- **Katman:** Pro.
- **Durum:** fikir — **v1 sonrası**, doğrulama sonrası. Maliyet modeli çıkarılmalı.

### Japonya tren zekâsı (NAVITIME tarzı transit)
- **Ne:** Peron numarası, aktarma yürüme süresi, Shinkansen, JR Pass kapsamı ile
  gerçek-zamanlı toplu taşıma yönlendirmesi.
- **Neden / kanıt:** NAVITIME'ın moat'ı (~¥330/ay). Google Maps Japonya'da bunu
  iyi yapmıyor. Japonya gezgininin gerçekten ödediği şey.
- **Mevcut kod:** Rota optimizasyonu var ama gerçek-zamanlı transit yok.
- **Maliyet:** ⚠ **Yüksek** — transit veri sağlayıcısı + entegrasyon. Büyük iş.
- **Katman:** Pro (ikinci kademe).
- **Durum:** fikir — uzun vade. NAVITIME'la doğrudan rekabet; ayrışma zor.

### Bilet / evrak kasası
- **Ne:** OCR'lanan biletler/rezervasyonlar kalıcı, aranabilir kasa.
- **Mevcut kod:** `ticket_ocr.dart` var; kalıcı kasa yok.
- **Maliyet:** Near-zero. Efor: 1–2 gün.
- **Katman:** Pro (ücretsiz 2 kayıt) — **MONETIZATION_PLAN Faz 3.5**.
- **Durum:** → taşındı.

### Ekiple plan paylaşımı
- **Ne:** Salt-okunur paylaşım linki (RLS ile).
- **Neden:** CLAUDE.md'de ikincil kullanıcı olarak tanımlı ama hiç yapılmamış.
- **Mevcut kod:** Supabase auth + RLS hazır.
- **Katman:** Pro — **MONETIZATION_PLAN Faz 3.6** (v1.1'e ertelenebilir).
- **Durum:** → taşındı.

---

## 2. Planlama-fazı retention özellikleri (aboneliğin can damarı)

> Abonelik ay 2–5 arası ancak "her ay bir sebep" varsa ayakta kalır
> (MONETIZATION_PLAN §2.4, §3.3). Bunlar o sebebi üretir.

### Zamana yayılı kalkış-öncesi hatırlatmalar
- **Mevcut kod:** `pre_departure_checklist_screen.dart` +
  `notifications_service` + `0003_pre_departure_checklist.sql` var.
- **Ne:** "Kalkışa 90/60/30/14/7 gün" tetikleyicileri — her biri kullanıcıyı
  geri getiren sebep.
- **Durum:** → MONETIZATION_PLAN Faz 3.3.

### Kur hareketinde güncellenen maliyet tahmini
- **Mevcut kod:** `0006_exchange_rates.sql` + `cost_estimate.dart`.
- **Ne:** JPY/TRY oynayınca "gezi tahmini ₺X değişti" bildirimi.
- **Durum:** fikir (Faz 3.3 kapsamında).

### Bütçe takibi (gerçek harcama girişi)
- **Mevcut kod:** `budget_screen.dart`.
- **Ne:** Plana karşı gerçek harcama; sapma gösterimi.
- **Durum:** fikir.

---

## 3. Ücretsiz kalması gerekenler — paywall'a KONMAZ

> Gerekçe: mağaza puanı, ağızdan ağıza yayılma ve **Türk/Müslüman gezgin için
> özgün ayrışma**. Bunlar para kapısı değil, büyüme motoru.

- 66 yemeklik Japon mutfağı rehberi + diyet/helal filtresi (`eats_screen.dart`
  — `premium_gates_test.dart` sözleşmesiyle kilitli)
- Japonca ifadeler + TTS, "Mutlaka Bilmeniz Gerekenler", acil durum bilgileri
- Hava durumu, pusula, checklist, statik bütçe tahmini
- Plan oluşturma + ilk günün ön izlemesi + "kazandırdığı saat" göstergesi
- 1 aktif gezi, 10 tarama/gün

---

## 4. Bağımsız fikir kovaları (ileride doldurulacak)

Henüz olgunlaşmamış, not düşülen yönler:

- **Digital Suica yardımı** — 2026'da fiziksel IC kart yok; Suica artık Apple
  Wallet'ta (¥500 min. yükleme). Tuzaklar + kurulum rehberi ücretsiz içerik
  olabilir; ödeme değil ama edinme/SEO değeri yüksek.
- **Sakura / mevsim zamanlama** — çiçeklenme tahminine göre rota önerisi
  (`sakura_overlay.dart` görsel katman zaten var).
- **Keşif oyunlaştırması derinleştirme** — `reward_map_screen.dart` XP/rütbe
  sistemi mevcut; sosyal/retention kolu olabilir.
- *(ekle...)*

---

## 5. Reddedilen / park edilen fikirler — yeniden önerme

> Silinmez ki bir sonraki oturum aynı fikri sıfırdan önermesin.

### AI itinerary üretimini paywall'a koymak
- **Reddedildi (2026-08-10):** AI planlama ücretsizleşti (Mindtrip, Wonderplan
  paywall'sız). Rotori'nin deterministik optimizer'ı doğru ama satış argümanı
  "akıllı planlama" **olamaz**. Rota optimizasyonu Pro'da satılır, ama "AI plan
  üretimi" olarak değil, "ulaşım süresi kazandırma" olarak konumlanır.

### Dil yardımı / acil durum bilgisini paywall'a koymak
- **Reddedildi:** Diyet/acil durum/dil bilgisi bir ödeme duvarının arkasına
  konmaz (`eats_screen.dart` yorumu + `premium_gates_test.dart`). Etik ve
  büyüme gerekçesi; DECISIONS 2026-08-10.

### Trip-pass'i ana model yapmak
- **Park edildi (hipotez açık):** Ana model abonelik; trip-pass reddedilmedi
  ama pazar kanıtı yetersiz. Yeniden değerlendirme kapısı: MONETIZATION_PLAN
  §9.2 (aylık/yıllık dağılımı sinyali).

---

## Kaynaklar

- [Wanderlog Pro özellikleri](https://help.wanderlog.com/hc/en-us/sections/13302911983643--Pro-features)
- [TripIt Pro](https://www.tripit.com/web/pro)
- [Layla AI planner tier list](https://layla.ai/blog/news-and-tips/ai-trip-planners-tier-list)
- [Mindtrip/Wonderplan karşılaştırma (paywall'sız AI)](https://monkeytravel.app/blog/best-ai-trip-planners-2026-compared)
- [Japonya tren uygulamaları 2026 + JR Pass kararı](https://www.jrpass.com/blog/the-best-japan-train-apps-for-tourists-in-2026)
- [Japonya uygulamaları 2026 + digital Suica](https://www.jrailpass.com/blog/best-apps-travel-japan)
