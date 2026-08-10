# CURRENT_TASK.md — Bugünün İşi

> Bu dosya *bugünkü* çalışmanın canlı görünümüdür. Her tamamlanan görevden
> hemen sonra güncellenir.

**Bugünün tarihi:** 2026-08-11
**Aktif branch:** `feat/premium-iap-foundation`
**Sprint hedefi:** Kullanıcı tarafından yeniden önceliklendirilen rota
deneyimi refactor'u. Mevcut deterministik rota algoritması korunacak; önce
çıktı sözleşmesi ve kullanıcıya gösterilen ulaşım ayakları iyileştirilecek.
Ana plan: `ROUTE_EXPERIENCE_REFACTOR_PLAN.md`.

> Branch adı önceki premium işini yansıtıyor. Bu refactor sırasında branch
> değiştirilmedi; kullanıcıya ait yerel değişiklikler korunuyor. Premium Faz 1
> işi iptal edilmedi, rota deneyimi başlangıç teslimatından sonra devam edecek.

---

## 🚦 SIRADAKİ OTURUM BURADAN BAŞLAR

### 2026-08-10 — Rota deneyimi refactor'u Faz 0–4 tamamlandı

**Kırmızı çizgi:** Beam search, beam width 6, yönlü matris, hard constraint,
must-do/fixed koruması, dört profil ve bağımsız validator ölçüm olmadan
değiştirilmeyecek.

**Şu anki sıra:**

1. ✅ Algoritma davranış sözleşmesini tek regresyon testiyle kilitle.
2. ✅ `RouteLeg` hat/yön/karmaşıklık bilgisini kayıpsız taşısın.
3. ✅ Saf `RouteExecutionLeg` adaptörünü ekle.
4. ✅ Ulaşım ayaklarını ön izleme ve kaydedilmiş günlük timeline'a bağla.
5. ✅ Versioned route snapshot, varsayım özeti, şehir geçişi ve bağlı bilet
   akışını tamamla.
6. ✅ Hedefli test + rota harness + analiz + dar ekran web QA çalıştır.
7. **Sıradaki:** Gerçek route sağlayıcısını seçip Edge Function ve kalıcı
   matrix cache'i uygulamak; ardından saha modu ve kalan kişiselleştirme.

Detay: `docs/ROUTE_EXPERIENCE_REFACTOR_PLAN.md`.

---

> Aşağıdaki monetizasyon işi rota deneyimi başlangıç teslimatından sonra devam
> edecek ikinci aktif iş paketidir. Devam ederken önce
> `docs/MONETIZATION_PLAN.md` okunur (özellikle §3 SKU'lar, §4 yayın kapsamı,
> §5 Faz 1, §9 karar günlüğü). **Model kararını yeniden tartışma** — §9.1'de
> kanıtın sınırları ve §9.2'de yeniden değerlendirme kapısı yazılı.

**Durum:** Faz 0 (App Store Connect ürün tanımları) **kullanıcıda**, henüz
yapılmadı. Faz 1 kodu başlamadı.

**Kullanıcı tarafında bekleyen (kod yazmayı bloke ETMEZ, sandbox testini eder):**

1. App Store Connect → abonelik grubu `rotori_pro`
   - `com.mennansevim.rotori.pro.yearly` — TR ₺499 / global $29.99,
     **7 gün ücretsiz deneme** introductory offer
   - `com.mennansevim.rotori.pro.monthly` — TR ₺99 / global $4.99,
     **deneme yok**
2. Small Business Program başvurusu (komisyon %30 → %15)
3. `rotori-social/data/automation_config.json` → `topic.enabled: false`
   açılacak mı? **Kullanıcıya sorulmuş, cevap alınmadı** — bilinçli
   kapatıldıysa dokunulmaz (bkz. `docs/GROWTH_SEO_STRATEGY.md` §6 sıra 1)

**Kod tarafında ilk iş:** aşağıdaki "Sıradaki Uygulama Adımı" listesi.

---

## Aktif Hedef

Monetizasyon modeli pazar araştırmasıyla kararlaştırıldı ve üç belgeye işlendi
(`MONETIZATION_PLAN.md`, `GROWTH_SEO_STRATEGY.md`, `DECISIONS.md` 2026-08-10
ve 08-10b). Model: **yıllık ₺499 + aylık ₺99 abonelik, yıllıkta 7 gün deneme,
kişiselleştirilmiş ön izleme hunisi.** Bu bir hipotez; ilk 100–200 nitelikli
kullanıcı verisinden sonra yeniden değerlendirilecek.

Sıradaki iş **Faz 1**: `in_app_purchase` entegrasyonu, Apple makbuz
doğrulaması yapan Edge Function, `subscriptions` tablosu, Apple S2S V2
bildirim endpoint'i ve `premiumProvider`'ın istemci-prefs'ten sunucu
yetkilendirmesine taşınması. Okuma tarafı (`is_premium()`) zaten var;
**yazan taraf ve süre kontrolü yok.**

Önceki sprint (rota optimizasyonu Faz 0–5) tamamlandı: schema v2, cross-day
assignment, priority-aware dropping, bağımsız hard validator, kişi/grup
maliyeti, transfer timeline, paired profil suite. 100 base × 4 profil kalite
kapısı geçti, analyze temiz.

## Tamamlananlar (bu ve önceki oturumlardan)

- ✅ **2026-08-11** Rotori Eats'teki **“Sadece yiyebileceklerimi göster”**
  filtresi katı güvenli moda alındı. Önceki davranış, uygun bir alt türü
  bulunan ana yemeği listede tutuyor ve kart üzerinde “Sorman gerek” veya
  “Uygun değil” hükmü göstermeye devam ediyordu. Anahtar açıkken artık yalnız
  doğrudan `DishVerdict.safe` yemekler listeleniyor; sayaç aynı filtrelenmiş
  kümeyi gösteriyor. Yemek/diyet testleri **45/45**, hedefli analiz temiz;
  iPhone 15 Pro web ön izlemesinde vegan filtre 66 yemekten 5 güvenli yemeğe
  indi ve görünür kartların tamamı “Yiyebilirsin” olarak doğrulandı.

- ✅ **2026-08-10** Gün bazlı etkinlik ekleme akışına **“Biletim /
  rezervasyonum var”** seçeneği eklendi. Biletli etkinlik ile bilet tek atomik
  komutta kimlik üzerinden bağlanıyor; ziyaret tarihi, sabit giriş saati,
  içeride geçirilecek süre ve erken-varış payı kalıcı saklanıyor. Bilet tarihi
  başka plan gününe denk gelirse etkinlik o güne taşınıyor; esnek duraklar hard
  rezervasyonun çevresine yeniden diziliyor. Yer detayından fotoğraf/OCR ile
  eklenen bilet de aynı komut hattını kullanıyor. USJ/Disney için 12 saat + 60
  dakika; teamLab türleri için ürün bazlı süre + 30 dakika varsayılanı var.
  Etkinlik bazlı erken-varış payı rota optimizer'ına aktarılıyor. Alt menüde
  silinen **Keşfet** butonu geri getirildi ve keşif haritasına bağlandı.
  Doğrulama: yeni domain testleri, plan motoru regresyonları ve iki dar mobil
  widget senaryosu geçti; değişen dosya analizi temiz, iPhone 15 Pro web
  önizlemesinde Keşfet görünümü doğrulandı.

- ✅ **2026-08-10** Deneyim rehberi ve Keşfet menüsü son kullanıcı odaklı
  yenilendi. Rehberdeki “Tümü / Tema parkları / teamLab” filtreleri kaldırıldı;
  oyuncak/deneyim stratejileri bir sonraki kartı görünür bırakan yatay kaydırma
  akışına alındı. USJ ve Tokyo Disney için ücretsiz resmî YouTube tanıtım
  bağlantıları eklendi. Her rehber, ziyaret tarihinden satış gününü hesaplayan
  Rotori hatırlatıcısına bağlandı. Hatırlatmalar ekranı artık Shinkansen
  (30 gün), Tokyo Disney ve USJ (60 gün), üç teamLab planlama hedefi için
  çoklu hazır seçim; her seçim için ayrı ziyaret tarihi; bildirim saatinin
  açık anlatımı ve serbest başlık/tarih/saatli özel hatırlatıcı sunuyor.
  Keşfet'te Premium **Fiyat etiketi tara** tam genişlik vitrin kartına çıktı,
  Rotori Eats dört sakin küçük karta taşındı; küçük kartlar düşük doygunluklu
  ortak yüzey diliyle yenilendi. Rota algoritması değiştirilmedi. Doğrulama:
  ilgili domain/widget/viewer testleri **42/42**, hedefli analyze temiz ve
  iPhone 15 Pro web ön izlemesinde etkileşim + yeni hata kaydı kontrolü temiz.

- ✅ **2026-08-11** Hatırlatıcı ürün sınırı Premium olarak netleştirildi:
  mevcut kayıtlar görülüp silinebilir, yeni hazır veya özel hatırlatıcı
  ekleme `premiumProvider` kapısından geçer. Hazır seçimlerde fotoğraf,
  emoji ve marka taklidi kullanılmıyor; altı ürün ayırt edici Material
  ikonları, kontrollü koyu gradyanlar ve ortak seçim diliyle nihai kart
  sunumuna sahip. Tokyo Disney ve USJ resmî site şartları
  ticari yeniden kullanıma izin vermediği, teamLab ticari kullanım için ön
  onay istediği için resmî fotoğraflar uygulamaya kopyalanmadı; resmî
  sayfalar bilgi/doğrulama bağlantısı olarak korunuyor. Rota algoritmasına
  dokunulmadı. Hatırlatıcı, deneyim rehberi, rezervasyon penceresi ve rota
  regresyonlarını kapsayan testler **46/46** geçti; hedefli analiz temiz ve
  iPhone 15 Pro web ön izlemesinde ücretsiz/Premium akışları ile taşma ve
  yeni hata kaydı kontrolü temiz.

- ✅ **2026-08-10** İlk kez gidecek kullanıcılar için iki dilli
  **“Bilet Hazır, Macera Başlasın!”** deneyim rehberi eklendi. Viewer keşfet
  menüsünden açılan enerjik sayfa; USJ, Tokyo Disneyland, Tokyo DisneySea,
  teamLab Planets, Borderless ve Botanical Garden Osaka için bilet alma
  adımlarını, giriş tamponunu, önerilen süreyi, saat saat akışı, içerideki
  öne çıkan deneyimleri ve kritik ipuçlarını tek yerde topluyor. Telifli
  park karakteri/logo içermeyen özgün hero görseli uygulama asset'i olarak
  üretildi; lisansı belirsiz üçüncü taraf tanıtım videosu gömülmeyip USJ'nin
  resmî video kanalına güvenli dış bağlantı verildi. Yeni domain/widget
  testleri **5/5**, viewer regresyonları **34/34** geçti; hedefli analiz temiz
  ve iPhone 15 Pro web ön izlemesinde görsel QA tamamlandı.

- ✅ **2026-08-10** Şehir geçişinden açılan bilet editörünün ESC ile
  kapatılmasında oluşan Flutter lifecycle assertion'ı giderildi. Editörün
  `TextEditingController` nesneleri dialog widget'ının gerçek yaşam döngüsüne
  taşındı; bilet dialog'u geçiş sheet'inin üzerinde açılıyor ve ESC yalnız üst
  dialog'u kapatıyor. Yeni ESC regresyonu dahil viewer testleri **26/26**,
  değişen dosya analizi temiz; web ön izlemesinde gerçek ESC ile doğrulandı.

- ✅ **2026-08-10** Rota deneyimi refactor Faz 2–4 ve Faz 5'in diyet güvenliği
  tamamlandı. Ön izleme ile kaydedilmiş plan timeline'ı artık çıkış/varış,
  ulaşım modu, süre, yürüyüş, gerçek transit beklemesi, aktarma ve grup
  ücretini gösteriyor. Tahmini sonuç hat/yön uydurmadan açık rozetle; güvenilir
  sonuç sağlayıcı hat/yön bilgisiyle gösteriliyor. `RouteExecutionSnapshot`
  schema v1 plan/gün/sürüm/aktivite hash'i/matris sürümü/profil/sağlayıcı
  kimliğiyle saklanıyor ve plan değişince geçersizleşiyor. Şehir geçişi modu
  ile bağlı bilet tek engine hattında düzenleniyor; bilet boş durumu CTA aldı.
  Oluşturma öncesi rota/tarih/uçuş/otel varsayımları görünür ve düzenlenebilir;
  eski JSON geriye uyumlu. Çelişen diyet seçimleri domain seviyesinde
  çözülüyor. Doğrulama: ilgili paket **94/94**, rota harness **15/15**,
  değişen dosya analizi temiz. Proje genel analyze yalnız refactor dışındaki
  mevcut **17** uyarı/bilgiyi raporluyor. Dar ekran web QA tamamlandı.

- ✅ **2026-08-10** Rota deneyimi refactor Faz 0/1 temeli tamamlandı.
  Algoritmanın beam 6, determinizm, sabit rezervasyon, gün sonu dönüşü ve
  bağımsız validator sözleşmesi `route_algorithm_contract_test.dart` ile
  kilitlendi. `RouteLeg`, matristen gelen `lineId`, `directionId` ve
  `complexityPenalty` bilgisini artık kaybetmiyor. Saf Dart
  `RouteExecutionBuilder`, optimizer bacaklarını başlangıç / duraklar arası /
  otele dönüş türleriyle ve reliable/estimated veri kalitesiyle sunum modeline
  çeviriyor; sonuç `PlanOptimizationPreview.executionLegs` üzerinden UI'a
  hazır. Hedefli rota testleri + harness **27/27**, daha geniş ilk rota paketi
  **29/29** başarılı; değişen 6 dosyanın analizi temiz. Proje genel analyze'da
  refactor dışı mevcut 18 uyarı/bilgi devam ediyor.

- ✅ **2026-08-10** Monetizasyon modeli pazar araştırmasıyla kararlaştırıldı ve
  belgelendi. Kod envanteri çıkarıldı: uygulama **hiç yayınlanmamış**
  (`version: 1.0.0+1`, release checklist'te işaretli kutu yok), ödeme
  altyapısı **sıfır** (`in_app_purchase` yok), sunucu yetkilendirmesinin
  **okuma tarafı var yazan yok** (`is_premium()`), rota optimizasyonu
  paywall'ı **satış değil coming-soon duvarı** ve kilidi istemcide
  (bypass edilebilir), l10n **%100 iki dilli** (1240/1240), sosyal hat
  kurulu ama otomasyon 2 gönderi yapmış. Araştırma: RevenueCat 2026
  (seyahat aboneliklerinin %66'sı yıllık, deneme→ödeme %43,5, indirme→ödeme
  medyanı %2, $1K MRR'a 238 gün, yeni seyahat uygulamalarının %9,8'i 2 yılda
  $10K MRR) + rakip modelleri (TripIt $49/yıl, Wanderlog $29.99–49.99/yıl +
  affiliate, Tripsy $59.99/yıl & lifetime $299 = yıllığın 5 katı çıpa,
  NAVITIME ~¥330/ay) + Wanderlog'un 5M indirmeye SEO ile çıkması.
  Karar: **yıllık ₺499 + aylık ₺99 abonelik, yıllıkta 7 gün deneme,
  kişiselleştirilmiş ön izleme hunisi** — "kanıtlanmış model" değil,
  **test edilecek en güçlü hipotez** (RevenueCat verisi yalnızca abonelik
  kullanan uygulamalardan geliyor → seçim yanlılığı; trip-pass hipotez
  olarak açık). Yayın kapsamı 26 → 12.5–15 güne indirildi; offline harita
  paketi, planlama fazı araçları, bilet kasası ve paylaşım yayın sonrasına
  ertelendi. Yeni belgeler: `docs/MONETIZATION_PLAN.md`,
  `docs/GROWTH_SEO_STRATEGY.md`. Commit: `8788454`, `396b6a0`.

- ✅ **2026-08-07** Yeni mobil **price-tag scanner** özelliği ayrı feature
  paketi olarak eklendi (`rotori-mobile/lib/features/price_tag_scanner/`):
  `view/` (tam ekran kamera + merkez viewfinder overlay), `controller/`
  (Riverpod state makinesi: Scanning → ExtractedData → FetchingMockPrices
  → ResultReady → Error, 450 ms frame throttling, single-flight OCR),
  `services/` (1 sn gecikmeli Hepsiburada/Trendyol/Amazon TR mock JSON fiyat
  repository) ve `utils/` (`TagParser`: JPY/model regex parse, ポイント
  eleme, 税込 önceliği). Test: `tag_parser_test.dart` (3 mock OCR bloğu)
  geçti; hedef kapsam analyzer temiz.

- ✅ **2026-08-07** Canlı fiyat çeviriciye ürün pazar sorgu akışı eklendi:
  kamerada sorgulanabilir ürün çerçevesi + `Fiyatı Sorgula` CTA, açılır
  sorgu sheet'inde Hepsiburada/Trendyol/Amazon kaynak ilerlemesi,
  kaynak bazlı fiyat/başarısızlık durumları, karşılaştırma özetinde
  TR medyan/min/max + JP referansı + fark (TL/%). Yeni `scanner.market.*`
  i18n anahtarları eklendi, resolver/controller/widget testleri yazıldı
  (`product_query_candidate_resolver_test`,
  `live_currency_scanner_controller_test`,
  `live_currency_scanner_page_query_ui_test`). Doğrulama:
  scanner hedef kapsamında `flutter analyze` temiz; ilgili test setleri yeşil.

- ✅ **2026-08-07** Viewer P0 test kırıkları güncel UI davranışına hizalanarak
  kapatıldı. `checklist_screen_test.dart`, `budget_screen_test.dart` ve
  `plan_viewer_test.dart` senaryoları yeni drawer/edit/bütçe yüzeyine göre
  stabilize edildi (eski `⋮` menü ve sabit toplam metni beklentileri
  kaldırıldı; drag/sheet/undo akışı doğrulandı). Doğrulama: hedefli viewer
  test paketi yeşil, ardından tam paket `flutter test` **+566 passed** ve
  `flutter analyze` temiz.

- ✅ **2026-08-06** rotori-social deploy hattı tek monorepo akışına alındı:
  Pi5'te bağımsız `~/rotori-social` git klonu arşivlenip çalışma dizini
  `~/rotori-app/rotori-social` oldu; servis bu dizinden rebuild edildi ve
  `commit=cbff51e` ile ayağa kalktı. Geriye uyumluluk için
  `~/rotori-social -> ~/rotori-app/rotori-social` symlink'i bırakıldı.
  Yerelde `social` remote kaldırılarak tek remote (`origin`) düzenine geçildi.

- ✅ **2026-08-06** rotori-social otomasyon zamanlama düzeltmesi:
  (1) `next_automation_slot` lane-aware hale getirildi; `news` ve `topic`
  otomasyonları artık slot hesaplamasında birbirini yanlışlıkla bloke etmiyor
  (legacy/manual kuyruk girdileri korumalı bloklayıcı kalıyor). Böylece
  "bugün +5 dk" gibi yakın zaman hedefleri başka lane çakışması yüzünden
  haftalara ötelenmiyor. (2) `news_automation` CLI `--publish` argümanını
  destekleyecek şekilde güncellendi; launchd auto_publish çağrısı artık
  geçerli akışa düşüyor (`run_once_with_publish`). (3) Regresyon testleri:
  `test_contracts_scheduler.py` yeni near-future lane izolasyonu + same-lane
  bloklama senaryoları ve `test_news_automation_cli.py` ile `--publish`
  kontratı eklendi. Hedef test setleri yeşil (9 + 58 test).

- ✅ **2026-08-06** Viewer kalite turu (kritik geri bildirim düzeltmeleri):
  (1) Akıllı rota sheet'inde "Güvenilir rota verisine ulaşılamıyor" diye
  maskelenen hatanın kök nedeni ayrıştırıldı; matrix fallback zaten varken
  optimizer infeasible kaldığında hard-error veriyordu. `PlanOptimizationController`
  artık `noFeasibleRoute/routeDataMissing/fixedConflict/protectedInfeasible`
  durumlarında **yerel kural tabanlı fallback preview** üretir (aktiviteleri
  korur, karşılaştırma kartı açılır, kullanıcı uygulayabilir). Ayrıca hata
  metinleri failure code'a göre ayrıştırıldı (`noFeasible`, `fixedConflict`,
  `routeDataMissing`, `dataIssue`) — simülasyon kaynaklı yanlış alarm azalır.
  (2) Drawer'daki "Yemek rehberi" aksiyonu artık must-know yerine yeni
  `FoodGuideScreen` açıyor; bu ekranda canlı birim maliyet tablosundan kısa
  fiyat referansları + aktif diyet tercihleri + pratik yemek ipuçları var.
  (3) "Mutlaka Bilmeniz Gerekenler" üst başlık çipleri, istek doğrultusunda
  dropdown filtreye çevrildi; "Tümü" veya seçili konuya göre alt içerik
  gösterilip gizleniyor. Hedef analiz temiz, controller testleri (9/9) yeşil.

- ✅ **2026-08-06** Route regression follow-up: `PlanViewerScreen` view modunun
  varsayılanı tekrar **aktif gün açık** olacak şekilde sabitlendi (rota
  aksiyonlarının görünürlüğü korunuyor). `plan_viewer_test` içindeki
  karşılaştırma/onay senaryosu, scrollable bottom sheet'te onay butonuna
  dokunmadan önce `ensureVisible` kullanacak şekilde stabilize edildi.
  Hedefli rota testleri yeniden yeşil.

- ✅ **2026-08-06** Keşif haritası rütbe-kazanım kutlaması okunabilirlik
  iyileştirmesi: eski tam ekran yarı-transparan metin katmanı yerine yüksek
  kontrastlı merkez kart + bulanık/karartılmış backdrop modeline geçirildi
  (örnek uygulamalardaki achievement modal desenine benzer). Yazı hiyerarşisi
  sadeleştirildi (label → romaji → açıklama → CTA), otomatik kapanış süresi
  hafif uzatıldı ve kutlama açıkken keşif/snackbar bildirimleri bastırılarak
  çakışma kaldırıldı.

- ✅ **2026-08-06** Mobil viewer yardımcılarında beş iyileştirme: (1) Rehber
  ("Mutlaka Bilmeniz Gerekenler") ekranına en üstte gruplanmış "Konu
  Başlıkları" hızlı erişim rozetleri eklendi (dokununca ilgili bölüme kaydırır)
  ve yeni "Acil Durum ve Güvenlik" bölümü (110/119, JNTO yardım hattı,
  sigorta, Safety tips app, büyükelçilik) yazıldı. (2) Canlı fiyat çevirici
  artık AR "yerinde" mod: çevrilen tutar algılanan fiyat kutusunun tam üzerine,
  opak zeminle yerleştiriliyor — kamera görüntüsünde fiyat sanki TL yazıyormuş
  gibi görünüyor. (3) Taraycıdan geri dönüş hatası düzeltildi: drawer artık
  `context.push` kullanıyor, geri tuşu plan listesine değil viewer'a döner.
  (4) Sandviç panel KEŞFET karoları yalnız-ikon yapıldı (etiketler kaldırıldı,
  erişilebilirlik için Tooltip/Semantics'e taşındı); sert beyaz zemin yumuşak
  accent tonuyla dengelendi. (5) Bütçe ekranına yıl bazlı, AI KULLANMAYAN
  tahmini gider dökümü eklendi: düzenlenebilir `assets/data/unit_costs.ini`
  birim maliyet tablosu (yetişkin/çocuk, mevsim çarpanı) + saf-Dart
  `cost_estimate.dart` tahmincisi (uçak/otel/yemek/tren/taksi/alışveriş/
  elektronik/gezi min–max) + "Bu rota sizin için ₺X – ₺Y" başlığı, kalem kalem
  satırlar ve örnek birim fiyatlar (ramen, shinkansen vb.). `flutter analyze`
  temiz; yeni `cost_estimate_test.dart` dahil 25 test yeşil.


- ✅ **2026-08-05** rotori-social otomasyon görünürlüğü iyileştirildi: yayın
  kuyruğu girdilerine son deneme zamanı/sonuç zamanı/deneme sayısı ve
  başarısızlık nedeni metadata alanları eklendi; dashboard aggregation
  (`/api/dashboard/publishes`, `overview`, `timeline`) artık
  `publish_outcome`, `publish_outcome_tr`, `failure_reason`, `is_overdue`
  alanlarını döndürüyor. Automation ekranına altta "Yayın Logu (Son
  Durumlar)" kartı eklendi; burada **başarılı/başarısız durum**, **yayın
  tarihi** ve **neden yayınlanmadı** bilgisi satır bazında görünüyor. Aşırı
  cache nedeniyle eski JS'in kalmaması için dashboard script cache-bust sürümü
  güncellendi.

- ✅ **2026-08-05** Viewer/yardımcı özelliklerde hızlı kalite turu:
  (1) Planlar ekranında çıkış için onay diyaloğu eklendi (yanlışlıkla logout
  riski azaltıldı), (2) Japonca TTS asset oynatma hızı cümle uzunluğuna göre
  normalize edildi (çok hızlı örnekler yavaşlatıldı), (3) Bütçe ekranına
  aile odaklı "güvenli üst limit" tahmini (JPY + TRY, aktarma/tek-yön
  varsayımlı) eklendi, (4) Must-know içine ATM/debit vs kredi kartı nakit
  avans limiti uyarısı güçlendirildi, (5) yer detay sheet'ine yakındaki
  restoranları haritada açan hızlı liste eklendi ve bilet-kaynağı modalinde
  daha güvenli Material/Ink etkileşimi kullanıldı, (6) canlı para tarayıcıda
  kamera/stream/OCR hata yolları için durum anahtarlı hata mesajları ve
  detaylı debug logları eklendi. `flutter analyze` temiz; scanner widget
  testleri yeşil. (Mevcut welcome-flow test kırıkları bu işten bağımsız olarak
  sürüyor.)

- ✅ **2026-08-03** Rota optimizasyon v2 Faz 0–5 çekirdek değişiklikleri:
  schema v2 + semantic determinism, `TripActivityAssignmentEngine`,
  `RouteOptimizationValidator`, enum priority/structured drop, transit
  wait–idle–freeTime ayrımı, return timeline, kişi/grup/araç maliyeti,
  `LuggageState`, transfer penceresi ve directional/time-slice estimated
  harness matrisi. 100 base × 4 paired profile benchmark hard/duplicate/
  must-do/return/estimated-warning kontrollerinde sıfır ihlal üretti; beam 6
  varsayılan kaldı. AI yalnız gerektiğinde onaylı/cache'li POI keşfi için tek
  batch; rota hesabı saf Dart.

- ✅ **2026-08-03** Final ürün benchmark'ı (seed `20260803`, beam 6): 100 gezi
  ve dört eş profilde 4.672 gün kaydı; 0 hard ihlal, 0 tekrar, 0 must-do
  düşürme, 0 eksik dönüş, 0 açıklanmamış uzun boşluk ve 0 infeasible gün.
  Düşürme oranı %1,77; cluster re-entry %0,94, Kyoto %0. En hızlı profil en
  kısa süreyi, az yürüyüş profili en az yürüyüşü, en ucuz profil en düşük grup
  maliyetini verdi. Aynı öncelikte öğün koruması için regresyon testi eklendi;
  rota prompt kalite eşiği yeniden geçti. `flutter analyze --no-pub` temiz.

- ✅ **2026-08-03** eski sosyal proje dizininin kaynak kodu
  doğrudan `rotori-social/` altına taşındı ve nested `.git`
  kaldırıldı. Böylece geçerli tek repository kökü `rotori-app/.git` oldu.

- ✅ **2026-08-03** Rota harness P0 doğruluk fixleri (`ROUTE_OPTIMIZATION_FIX_PLAN.md`
  Faz 1) çekirdeğe dokunmadan uygulandı: (1) yemek yeri çalışma saatleri
  korunuyor — `MealPeriod` + `servesMeal`, market'ler yalnız öğle, her şehre
  akşam servisi veren gerçek lokantalar + sentetik fallback+warning; (2) tam
  gün/uzak gezi izolasyonu `PoiDayRole` ile magic number'dan kurtarıldı ve
  refill sonrası çalışıyor (USJ/DisneySea/Miyajima artık başka POI ile
  karışmıyor); (3) <50 m co-located leg sıfırlandı (yapay kahvaltı yürüyüşü
  gitti). Ölçülen: kapalı-market akşam yemeği 0, walk>0 kahvaltı 0, park/Miyajima
  karışması 0, düşürülen aktivite 365→218. `test/tool/route_opt_harness_test.dart`
  9 test yeşil; `flutter analyze` (harness) 0 error.


- ✅ **2026-08-02** Canlı kamera para birimi çevirici (`live_currency_scanner`)
  uçtan uca eklendi: cihaz-üstü OCR (ML Kit, web'de no-op koşullu export),
  saf-Dart normalizer/parser/tracker/coordinate-transformer/converter,
  Supabase `exchange_rates` migration'ı (0006, herkese-okuma RLS, istemci
  yazamaz), SharedPreferences kur cache + manuel kur, ayarlar ekranı
  (hedef para birimi, otomatik güncelleme, kart farkı, yuvarlama, performans
  profili), Apple-kalite kamera overlay + izin/hata ekranları, TR/EN i18n,
  iOS `NSCameraUsageDescription` güncellemesi + Android `CAMERA` izni.
  `flutter analyze` temiz; 60 yeni test yeşil.

- ✅ **2026-08-02** Rütbe kanjileri için Noto Sans JP alt-kümesi (subset) fontu
  eklendi. Yalnızca kullanılan 11 glif (狸狐河童天狗鶴麒麟鳳凰龍旅) alınıp 700
  ağırlığa sabitlenerek `assets/fonts/NotoSansJP-Rank.ttf` (~5.9 KB) üretildi;
  `NotoSansJPRank` ailesi olarak `pubspec.yaml`'a kaydedildi ve madalyon /
  kutlama / drawer marka (旅) metinlerine uygulandı. Web'deki "Could not find a
  set of Noto fonts" uyarısı çözüldü; kanji tüm platformlarda net render edilir.
- ✅ **2026-08-02** Keşif haritasına Ghibli esintili rütbe-atlama kutlaması
  eklendi: XP ile rütbe kademesi arttığında yumuşak sıcak ışık, yukarı süzülen
  toz zerreleri (susuwatari) + altın parıltı ve nazikçe beliren ışıklı madalyon
  gösterilir; `HapticFeedback.mediumImpact` ile eşlenir, ~2.8 sn sonra
  kendiliğinden kapanır (dokunarak da kapanır). Açılışta tetiklenmez —
  yalnızca gerçek rütbe artışında. `flutter analyze` temiz, qa geçti.

- ✅ **2026-08-02** Keşif haritası (`reward_map_screen.dart`) baştan tasarlandı:
  XP odaklı "Gezgin rütbesi" — 狸 Tanuki → 龍 Ryū 8 kademeli Japon efsane
  yaratıkları merdiveni (her 100 XP bir rütbe, `xpToLevel` ile birebir).
  Degrade kanji madalyonu + romaji/anlam + toplam XP + sonraki rütbeye kalan
  XP çubuğu; keşif metrik şeridi; sakin konum-takibi ipucu ve kartı;
  aktivite rozetleri pasif liste görünümü. `CityCard` yeniden yazıldı —
  ViewerPalette uyumlu, gezilmemiş noktalar pasif halka, gezilen yeşil onay,
  tespit amber; tabular figürlerle hizalı sayılar. `flutter analyze` temiz,
  qa_scenarios (TR/EN rütbe anahtarları dahil) geçti.

- ✅ **2026-08-01** Boş uçuş/otel bölümleri pasif collapsible yerine
  planlayıcının düzenleme adımına götüren dokunulabilir `_DrawerAddCard`
  ile değiştirildi (`drawer.flights.add` / `drawer.hotels.add` / `drawer.add.hint`).
- ✅ **2026-08-01** Panel bilgi hiyerarşisi sadeleştirildi: "Bug bildir"
  ARAÇLAR'dan HESAP grubuna alındı; ARAÇLAR yalnızca sık kullanılan
  Hatırlatmalar/Tema/Google Maps'i tutuyor.
- ✅ **2026-08-01** `plan_viewer_screen.dart` 7125 → 5626 satıra indi: sandvich
  drawer widget ailesi (~1500 satır) davranış birebir korunarak
  `widgets/plan_viewer_drawer.dart` part dosyasına taşındı. `part of` ile
  private erişim ve paylaşılan importlar aynen sürüyor; `flutter analyze`
  temiz, test farkı yok (mevcut edit-mode/checklist hataları değişiklikten
  önce de vardı).
- ✅ **2026-08-01** Viewer hamburger (sandvich) paneli görsel olarak yenilendi:
  `assets/images/hamb-menu-top-bg.png` hero görseli `cover` + okunabilirlik
  scrim'i + palete akan alt gradyanla üst başlığa yerleştirildi; marka rozeti
  gölge/halka ile fotoğrafın üstünde okunur oldu, cam efektli kapatma düğmesi
  eklendi. Yolculuk özet kartı başlık/badge tekrarından arındırılıp sade üç
  metrik şeridine indirildi. `flutter analyze` temiz; qa_scenarios geçti.

- ✅ **2026-08-01** Uygulama kabuğu `AppTheme.light`, viewer yeni kurulum
  varsayılanı `appleLight` oldu; kaydedilmiş `viewer:theme` tercihi korunuyor.
- ✅ **2026-08-01** Hamburger menüsü küçülten `FittedBox` yapısından çıkarılıp
  Yolculuk/Keşfet/Araçlar/Hesap hiyerarşisi, iki sütunlu hızlı aksiyonlar,
  gruplanmış ayar satırları ve gerçek küçük-ekran kaydırmasıyla yenilendi.
- ✅ **2026-08-01** TR/EN menü anahtarları ve tema/menu regresyonları eklendi;
  `flutter analyze` temiz, hedefli tema ve drawer testleri başarılı. Çalışan
  Chrome Flutter oturumu hot restart ile güncellendi.
- ✅ **2026-07-22** Marka ismi Rotori olarak rebrand + sitede/uygulamada
  tutarlı hale getirildi (`360e5ae`).
- ✅ **2026-07-29** Mobil planner/viewer refaktörü ve site cilası commit edilip
  gönderildi (`f9b1207`).
- ✅ **2026-07-29** Hero görseli `rotori-hand-mobile.svg` adıyla yayın asset'i
  olarak sabitlendi (`4c0f735`).
- ✅ **2026-07-30** Hero “Planla / Yolculuk / Sahada” öğeleri erişilebilir
  bölüm bağlantılarına dönüştürüldü; aktif durum ve kaydırma doğrulandı.
- ✅ **2026-07-30** Altı Japonca kategori uygulamadaki yerel MP3'lere bağlandı;
  oynat/durdur, kategori seçimi, TR/EN metinleri ve romaji görünümü doğrulandı.
- ✅ **2026-07-30** Site genelindeki TR/EN pazarlama metinleri baştan sona
  gözden geçirildi; belirsiz vaatler somut fayda ve gizlilik açıklamalarıyla
  değiştirildi.
- ✅ **2026-07-30** Hero el ve telefon SVG'si masaüstünde %40 büyütüldü;
  Japonca cümle kartı %40 küçültüldü ve sesler 0,78× hızda oynatıldı.
- ✅ **2026-07-30** Hero sahnesi referanstaki merkez telefon, iki yandaki
  katmanlı bildirimler ve görsele binen koyu aşama çubuğuyla yeniden düzenlendi.
- ✅ **2026-07-30** Güven kartları geniş ekranda 6×1, orta ekranda 3×2,
  mobilde 1×6 olacak şekilde dengelendi.
- ✅ **2026-07-30** Alışveriş ses örneği “Kaado wa tsukaemasu ka?” /
  “Kart kullanabilir miyim?” cümlesi ve eşleşen MP3 ile değiştirildi.
- ✅ **2026-07-30** Hero sahnesi 1.600 px maksimum genişlikte ortalandı;
  2.048 px ekranda iki yanda 224 px, mobilde 36 px güvenli boşluk doğrulandı.
- ✅ **2026-07-30** Referans site oranına göre hero sahnesi 1.400 px'e,
  el/telefon 520 px'e ve bildirim kartları 460 px'e indirildi; sahne yüksekliği
  901 px'den 759 px'e düşürüldü.
- ✅ **2026-07-30** Hero sahnesi en fazla 1.120 px ve ekranın %84'ü olacak
  şekilde daraltıldı; el/telefon 460 px, bildirim kartları en fazla 400 px oldu.
- ✅ **2026-07-30** Hero sahnesindeki sağ bildirim kartları telefona 75–86 px
  yaklaştırıldı; 1.280 px ve 1.024 px genişliklerde yatay taşma olmadığı
  doğrulandı.
- ✅ **2026-07-30** Hero bildirim kartları iki tarafta telefonun arkasına
  bitişecek biçimde içeri alındı; 1.280 px ve 1.024 px genişliklerde katmanlama
  ve yatay taşma kontrol edildi.
- ✅ **2026-07-30** Hero bildirimlerindeki başlık, alt açıklama ve zaman
  etiketleri TR/EN için kelime başları büyük olacak biçimde düzenlendi.
- ✅ **2026-07-30** Hero kartlarının dış boşluklarını kartları ayrı ayrı
  taşıyarak eşitleme denemesi yapıldı; kompozisyonu bozduğu için sonraki
  düzenlemede geri alınmasına karar verildi.
- ✅ **2026-07-30** Sol bildirimler, telefon/el ve sağ bildirimler tek bir
  görsel blok olarak ortalandı; merkez sapması 1.280 px ve 1.024 px
  genişliklerde 0 px, yatay taşma 0 px ölçüldü.
- ✅ **2026-07-30** `website/` altındaki tüm `teamLab` marka yazımları
  `TeamLab` olarak düzeltildi; TR/EN sözlüklerinde eski yazım kalmadı.
- ✅ **2026-07-30** Site değişiklikleri `japan-trip` (`da3a659`) ve yayın
  paketi `rotori-web` (`fa5d353`) depolarına gönderildi; Pi deploy'u
  tamamlandı, container healthy ve `https://rotori.app` HTTP 200 doğrulandı.
- ✅ **2026-07-22** Website F1 seti (privacy + support + footer link + copy
  tazeleme) — `08d7449`, `cbd592a`.
- ✅ **2026-07-22** F1 App Store hazırlığı: Info.plist, hesap silme, aydınlık
  mor tanıtım (`11f3541`).
- ✅ **2026-07-2x** Design System v2 devreye alındı (`4578280`).
- ✅ F2.0 test regresyonları çözüldü — `plan_viewer` + `day_map` (`70c82d2`).
- ✅ Daha önce: Supabase auth uçtan uca (`233a57e` · Google OAuth),
  QA framework 100 senaryo (`13969b9`, `888feb2`), viewer satır içi düzenleme
  (`e66429c`), top-down shinkansen planı (`c7ef17f`).
- ✅ **2026-07-30** Saf Dart `PlanScheduleEngine` ile gün içi/günler arası
  taşıma, yeniden sıralama, saat/süre, ekleme/silme, gün başlığı/tarihi ve gün
  sırası komutları tek immutable işlem hattında toplandı.
- ✅ **2026-07-30** Çakışma, o tarihte geçerli 30 dakikalık yemek boşluğu, gün sınırı, tekrar
  eden komut ve sabit rezervasyon kuralları typed failure'larla güvenceye
  alındı.
- ✅ **2026-07-30** Uçuş/varış, otel check-in/out ve satın alınmış biletler
  açık lock/capability metadatasıyla geriye uyumlu JSON modeline taşındı.
- ✅ **2026-07-30** `PlanEditSession` optimistic update, seri kayıt, yerel
  yazma hatasında rollback, undo ve remote snapshot yenilemesini uyguladı.
- ✅ **2026-07-30** Viewer'a uzun-bas drag/drop, gün hedefi vurgusu, kapalı
  günü bekleyince açma, sabit satır görünümü, haptic geri bildirim ve
  erişilebilir “güne taşı” alternatifi eklendi; planner aynı motora bağlandı.
- ✅ **2026-07-30** Küçük ekran ve dark mode web preview elle kontrol edildi.
  `flutter analyze` temiz, tam test paketi 370/370 başarılı.
- ✅ **2026-07-30** Osaka yer sayısı (9), toplam geofence koordinat kapsamı
  (52) ve ilgili testler güncel veriyle doğrulandı.
- ✅ **2026-07-30** Eski plandaki ilgisiz transfer/check-in çakışmasının
  akşam yemeğini 19:30'dan 18:30/17:30'a alma ve günler arası taşıma
  komutlarını engellemesi düzeltildi. Motor artık yalnızca yeni veya büyüyen
  zaman çakışmasını reddediyor.
- ✅ **2026-07-30** Demo üzerinde 17:30 saat kaydı, menüden 2. güne taşıma ve
  hedef günde 16:15'e yeniden saatleme elle doğrulandı. Menü ve uzun-bas
  drag/drop için widget regresyonları eklendi; `flutter analyze` temiz,
  tam paket 374/374 başarılı.
- ✅ **2026-07-30** Edit Engine ortak 15 dakikalık aktivite/yemek tamponuna
  geçirildi. Saat değişikliğinde seçilen aktivite korunup aynı günün devamı;
  günler arası taşımada kaynak ve hedef gün otomatik yeniden saatleniyor.
- ✅ **2026-07-30** 08:00–22:00 arasındaki 15 dakikalık slot ızgarası eklendi.
  Geçersiz saatler gri ve pasif; hedef günde boşluk yoksa kaydetme kapalı ve
  “Bu günde uygun zaman aralığı bulunamadı.” bilgisi gösteriliyor.
- ✅ **2026-07-30** Menüden taşıma ve uzun-bas drag/drop aynı uygun-saat
  seçimini açıyor; kenar sürüklemede auto-scroll, lift/gölge, hedef gün
  highlight ve haptic davranışları birlikte çalışıyor.
- ✅ **2026-07-30** Flight/Train Arrival ve Departure satırlarının eski
  planlarda da gün/saat/sıra/drag yetenekleri kapatıldı. Başarılı mutasyon
  sonrası undo yalnızca 5 saniyelik snackbar üzerinden sunuluyor.
- ✅ **2026-07-30** Yeni domain/widget regresyonları dahil `flutter analyze`
  temiz, tam mobil test paketi **380/380 başarılı**.
- ✅ **2026-07-30** Aksiyonlu snackbar'ın erişilebilirlik modunda süresiz açık
  kalması düzeltildi; uygulama tarafındaki zamanlayıcı undo yüzeyini her
  durumda 5 saniye sonunda kapatıyor.
- ✅ **2026-07-30** Viewer hamburger menüsünde konaklama sonrası içerik
  referansa göre yeniden sıralandı: üçlü metrikler, dört yuvarlak Keşfet
  kısayolu, dört satırlı Araçlar kartı, profil ve hesap/navigasyon işlemleri.
  Tema ve tüm rotayı Google Maps'te açma işlevleri ikincil satır olarak
  korundu.
- ✅ **2026-07-30** Hamburger menü web preview'de üst ve alt bölümleriyle
  görsel kontrol edildi; temiz hot restart sonrasında konsol hatası yok.
  `flutter analyze` temiz, güncel tam mobil paket **381/381 başarılı**.
- ✅ **2026-07-30** Günlük “Haritada gör” ekranında duraklar kırmızı numaralı
  noktalarla gösterilip beyaz konturlu kırmızı rota çizgisiyle birbirine
  bağlandı. Web preview'de görsel doğrulandı; `flutter analyze` temiz ve
  günlük harita widget testleri **4/4 başarılı**.
- ✅ **2026-07-30** Harita doğrudan URL ile açıldığında geri okunun tepkisiz
  kalması düzeltildi. Geçmiş yoksa ilgili plan görünümüne güvenli dönüş
  yapıyor; çalışan web preview üzerinde rota değişimi elle doğrulandı.
- ✅ **2026-07-30** Yönlü kapıdan kapıya rota matrisi, yedi ulaşım modu,
  deterministik fake repository ve sağlayıcıdan bağımsız backend gateway
  sözleşmesi eklendi; mobil uygulamaya API anahtarı konulmadı.
- ✅ **2026-07-30** Beam width 6 kullanan saf Dart optimizer; hard feasibility
  pruning, artımlı state, local swap/move, geri dönüş/küme/aktarma maliyetleri
  ve Balanced/Fastest/Least Walking/Cheapest profilleriyle tamamlandı.
- ✅ **2026-07-30** Tokyo, Osaka, 14:00 sabit rezervasyon, kapanış/minimum süre,
  otel dönüşü, ulaşım profili ve yönlü matris regresyonları eklendi.
- ✅ **2026-07-30** Rota cache anahtarı koordinat hassasiyeti, yön, ulaşım
  modu, gün tipi, zaman dilimi, profil ve sağlayıcıyı kapsayacak biçimde
  modellendi; primary/alternative/stale fallback ve typed failure eklendi.
- ✅ **2026-07-30** AI review policy, bütçe/model/token config'i, yapılandırılmış
  çıktı, scope doğrulama ve cache eklendi. Normal optimizasyonda AI çağrısı
  yok; AI hatası deterministik rotayı veya kaydı bozmuyor.
- ✅ **2026-07-30** Riverpod `PlanOptimizationController`, mevcut
  `TimelineItem` modelini adapter ile kullanarak eski/yeni metrik ön izlemesi,
  açık onay, vazgeçme ve plan-version/activity-hash sonuç cache'i sağladı.
- ✅ **2026-07-30** Birleştirilmiş rota optimizasyon çalışmasında
  `flutter analyze` temiz ve tam mobil test paketi **416/416 başarılı**.
- ✅ **2026-07-30** Viewer gün kartına “Rotayı optimize et” eylemi eklendi.
  Dengeli/En hızlı/Az yürüyüş/En ucuz profilleri, yükleme/hata durumları,
  Önce/Sonra ulaşım-yürüyüş-aktarma-maliyet karşılaştırması ve açık
  “Rotayı uygula / Vazgeç” onayı tek bottom sheet'te bağlandı.
- ✅ **2026-07-30** Optimizasyon sonucu onaydan önce kalıcı planı değiştirmiyor;
  onayda repository + edit session + home widget birlikte yenileniyor.
  Güvenilir koordinat veya route matrix yoksa plan korunup anlaşılır hata
  gösteriliyor. QA preview deterministik fake matrix ile elle doğrulandı.
- ✅ **2026-07-30** Web'de üst bar zilindeki üçüncü taraf ikon getter'ının
  oluşturduğu stack overflow Material ikonla giderildi. `flutter analyze`
  temiz, tam mobil test paketi **418/418 başarılı** ve temiz preview açılışında
  konsol hatası yok.
- ✅ **2026-07-30** Gelecekteki ilk gezi gününün bugünün saatine göre yanlışlıkla
  “geçmiş” sayılıp soluk gösterilmesi düzeltildi. Saat karşılaştırması artık
  yalnız plan tarihi bugünse çalışıyor; gelecek günün ilk aktivitesi doğru
  “Sıradaki” öğe oluyor. `flutter analyze` temiz, viewer testleri **19/19**
  başarılı.

## Kalanlar (kısa vadeli)

- [ ] **Viewer sheet kapanma ergonomisi (Apple uyumlu)**
  - Alt açılır detay sayfasında kapanma etkileşimi zor hissediliyor.
  - İyileştirme: drag-to-dismiss hassasiyet ayarı, üstte görünür `Kapat (X)` aksiyonu,
    dış alana dokunarak kapatma (modal kısıtları uygunsa) ve scroll/drag çakışmasını azaltma.
  - Kabul kriteri: tek elle kullanımda ilk denemede kapanma oranı artmalı,
    uzun içerikte sheet "takılıyor" hissi belirgin şekilde azalmalı.

- [ ] **Timeline saat kolonu boşluk optimizasyonu**
  - Soldaki saat ve timeline ray etrafındaki yatay boşluk fazla; içerik alanı daralıyor.
  - İyileştirme: saat kolonu genişliğini ve saat-sol/sağ padding'i küçült,
    kart içeriğine daha fazla alan aç.
  - Kabul kriteri: küçük ekranlarda (özellikle iPhone dar genişlik) satır taşması azalmalı,
    görsel denge korunmalı.

- [ ] **GPS akıllı takip (pil dostu, kullanıcıyı yormayan model)**
  - Hedef: Kullanıcının bazı bölgelerde ~10 dakika kaldığını tespit etmek,
    sürekli açık GPS zorlamadan ve her seferinde manuel açtırmadan.
  - Önerilen yaklaşım (Apple doğasına uygun): Visit + Significant Location +
    dinamik geofence + kısa süreli yüksek doğruluk burst doğrulaması.
  - Ürün yüzeyi: tek ana anahtar (`Akıllı Konum Takibi`), gezi tarih aralığında
    otomatik aktif/pasif, pil modu seçenekleri (Tasarruf/Dengeli/Hassas).
  - Kabul kriteri: 10 dk kalış tespiti false positive üretmeden çalışmalı,
    pil tüketimi "always-on GPS" seviyesine çıkmamalı.

- [ ] Supabase Edge Function veya mevcut backend üzerinde gerçek route matrix
  gateway'ini uygula; sağlayıcı seçimi ve gizli anahtarlar sunucuda kalsın.
- [ ] Bellek içi rota/ön izleme cache'lerini cihazda kalıcı cache'e taşı.
- [ ] Planner içine görünür optimizasyon karşılaştırmasını ve günler arası
  taşımada iki-günlük atomik coğrafi ön izlemeyi bağla.
- [ ] Büyük Japonya istasyonları için tek merkezli metadata/tampon kaynağını
  backend route normalizasyonuna ekle.
- [ ] Kök `img/hand-mobile.svg` tasarım kaynak dosyasıdır. Yayında bunun
  `website/img/rotori-hand-mobile.svg` adlı kopyası kullanılır; kök kopya
  deploy paketine girmez.
- [ ] Supabase Auth "Confirm email" prod öncesi **aç** (hâlâ kapalı — `[[supabase-backend]]`).
- [ ] App Store submission checklist — Sign in with Apple Services ID
  yapılandırması ($99/yıl Developer + Services ID) — `[[supabase-backend]]`.

## Bilinen Blocker'lar

- Native `integration_test` koşusu için bağlı iOS/Android cihaz veya emulator
  yok. Web integration runner desteklenmiyor; macOS desktop hedefi projede
  yapılandırılmamış. Aynı kritik sözleşmeler normal Flutter test paketinde
  çalışıyor.
- Sunucuda plan revision/CAS alanı yok; aynı plan iki cihazda aynı anda
  değiştirilirse cihaz içi sıra ve dirty-cache korumasına rağmen son yazan
  kazanabilir.

## Sıradaki Uygulama Adımı — Faz 1 iş emri (v2, düzeltilmiş)

> **Mimari sözleşme: `docs/ARCHITECTURE.md` §8b.** Ürün/fiyat kararı:
> `MONETIZATION_PLAN.md`. Bu liste sıralı yürütülür; §8b'den sapma olursa
> önce §8b güncellenir (proje kuralı: koddan önce doküman).
>
> **Bu listenin v1'i iki ciddi hata içeriyordu** (dış inceleme yakaladı,
> 2026-08-10): (a) `original_transaction_id` unique + `transactionId`
> idempotency'si tutarsızdı — ikisi farklı kimlik, ilki abonelik ömrü boyunca
> sabit, ikincisi her yenilemede değişir; tek tabloda birleştirmek
> yenilemeleri kırar. (b) Yetki kaynağı olarak `raw_user_meta_data`
> öneriliyordu — **bu alan kullanıcı tarafından yazılabilir**, yetkilendirmede
> kullanılamaz. İkisi de aşağıda düzeltildi.

### 1. Üç tablolu şema — `supabase/migrations/0009_subscriptions.sql`

- [ ] `subscription_entitlements` — güncel durum,
      `original_transaction_id` **UNIQUE**; alanlar §8b.2'de
- [ ] `app_store_transactions` — değişmez geçmiş, `transaction_id` **UNIQUE**
      (gerçek replay koruması burada; her yenileme yeni satır)
- [ ] `app_store_notifications` — `notification_uuid` **UNIQUE**
      (bildirim idempotency'si)
- [ ] RLS: self-read; INSERT/UPDATE yalnız service_role
      (`0008_daily_scans.sql` deseni)
- [ ] Tüm `SECURITY DEFINER` fonksiyonlarda `set search_path = public`,
      açık `REVOKE`/`GRANT`
- [ ] `subscription_entitlements.user_id` için cascade delete **dikkatli** —
      §8b.9 (yasal saklama vs hesap silme)

### 2. `is_premium()` tabloya bağlanır — **mevcut güvenlik açığını kapatır**

- [ ] `is_premium()` yeniden yazılır: **yalnız `subscription_entitlements`**
      okur (§8b.3 sorgusu). `raw_user_meta_data` yetkilendirmede **hiç
      kullanılmaz** — kullanıcı o alanı `auth.updateUser` ile kendisi
      yazabiliyor, yani şu an tarama kotası (10/100) aşılabilir durumda
- [ ] `expires_at` **veya** `grace_period_expires_at` geçerliyse aktif;
      `refunded`/`revoked` her durumda kapalı
- [ ] **`parse-price-tag/index.ts:178` bu fonksiyonu çağırıyor** —
      imza korunur, tarama kotası regresyona girmez

**Kabul:** Süresi geçmiş abone `false`; grace period içindeki abone `true`;
iade edilmiş abone `false`; metadata'sını elle `premium: true` yapan kullanıcı
`false`; tarama kotası testleri yeşil.

### 3. JWS doğrulama + hesap sahipliği — `supabase/functions/verify-purchase/`

- [ ] App Store Server API ile `signedTransactionInfo` **JWS imza**
      doğrulaması (legacy `/verifyReceipt` kullanılmaz)
- [ ] `bundleId` (`com.mennansevim.rotori`) + `productId` + `environment`
      + `expiresDate` doğrulanır
- [ ] **`appAccountToken` sahiplik kontrolü** (§8b.4): JWS içindeki değer
      oturumdaki Supabase `user_id` ile eşleşmezse yetki **açılmaz**
- [ ] `app_store_transactions`'a `transaction_id` ile idempotent insert;
      `subscription_entitlements`'a `original_transaction_id` ile upsert
- [ ] Yetki **yalnız tabloya** yazılır; metadata'ya yazılmaz (§8b.1)

### 4. S2S V2 endpoint + reconciliation — `supabase/functions/apple-notifications/`

- [ ] `signedPayload` imza doğrulaması
- [ ] `notification_uuid` ile idempotent kayıt (tekrar gelen bildirim iki kez
      işlenmez)
- [ ] Olaylar: `SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW`,
      `GRACE_PERIOD_EXPIRED`, `EXPIRED`, `DID_CHANGE_RENEWAL_STATUS`,
      `DID_CHANGE_RENEWAL_PREF`, `REFUND`, `REVOKE` — **durum makinesi
      §8b.5'e göre**, olay adına göre düz `switch` değil
- [ ] **Eski bildirim yeni durumu ezmez** (sıra dışı teslim korumalı)
- [ ] Şüpheli/eksik durumda `Get All Subscription Statuses` ile uzlaştırma
- [ ] Production ve sandbox endpoint'leri **ayrı**; Notification History
      kurtarma yolu tanımlı
- [ ] `grace_period_expires_at` Apple'ın verdiği değerden yazılır — elle
      "tolerans" hesaplanmaz

**Neden atlanamaz:** Bu olmadan iptal/iade sonrası erişim süresiz açık kalır.

### 5. İstemci — `rotori-mobile/lib/features/premium/purchase_service.dart`

- [ ] `in_app_purchase: ^3.3.0` + **`in_app_purchase_storekit: ^0.4.11`**
      (JWS `serverVerificationData` 0.4.2'de, deneme uygunluğu 0.4.3'te geldi;
      3.3.0 iOS'ta StoreKit 2'yi varsayılan kullanıyor). **v1'deki `^3.2.0`
      JWS planıyla uyumsuzdu**
- [ ] `purchaseStream` dinleyicisi **uygulama açılışında en erken** kurulur
- [ ] Satın alırken Supabase UUID `appAccountToken` olarak verilir (§8b.4)
- [ ] Sunucu doğrulaması → yetki → **`completePurchase()`** (3 gün içinde
      tamamlanmayan işlem iadeye yol açabilir)
- [ ] **Kalıcı "bekleyen doğrulamalar" kuyruğu** — doğrulama sırasında ağ
      koparsa işlem kaybolmaz, bağlantı gelince tekrar denenir
- [ ] `restorePurchases()`
- [ ] Hata durumları: mağaza erişilemez, ürün yok, ödeme reddedildi,
      pending (Ask to Buy / SCA), ağ yok
- [ ] **Deneme uygunluğu StoreKit 2 intro eligibility API'sinden** okunur —
      yerel `trial_used` anahtarı **kullanılmaz** (reinstall/çoklu cihazda bozulur)

### 6. `premiumProvider` — cache yalnız UI (§8b.6)

- [ ] Tek doğru kaynak sunucu; cache **yalnız arayüz kolaylığı**
- [ ] Ücretli sunucu işlemleri (AI rota keşfi, tarama kotası) her zaman
      backend'de korunur — cache'e güvenilmez, kırılması gelir sızıntısı değil
- [ ] Cache'e son güvenilir **sunucu zamanı** yazılır (cihaz saati geri
      alınabilir)
- [ ] `kPremiumPrefsKey` → `'premium_entitlement_cache'`; debug override ayrı
      anahtara (`'debug_premium_override'`), yalnız `kDebugMode`
- [ ] `price_tag_scanner/controller/scanner_controller.dart:268` aynı anahtarı
      okuyor — birlikte güncellenir

### 7. Testler

- [ ] `premium_gates_test.dart` yeniden yazılır — satır 67–71 eski prefs
      sözleşmesini kilitliyor, **kasıtlı kırılacak**. Eats ücretsizliği
      testleri (80–99) **aynen korunur**
- [ ] Sunucu tarafı senaryo matrisi: yanlış JWS imzası · yanlış
      bundle/product/environment · başka kullanıcıya ait `appAccountToken` ·
      aynı `transaction_id` tekrarı · aynı `notification_uuid` tekrarı · eski
      bildirimin yeni yenilemeyi ezmemesi · grace period başı/sonu ·
      aylık↔yıllık geçiş · refund/revoke · hesap silinmişken S2S bildirimi ·
      ağ kesikken satın alma + yeniden doğrulama · restore + yeniden kurulum ·
      tarama kotası regresyonu
- [ ] **"Release build'de debug override okunmuyor" unit testle
      kanıtlanamaz** — Flutter unit testleri debug modda koşar, `kDebugMode`
      true. Bunun için **release-mode cihaz smoke testi** gerekir

### 8. Hukuki metinler ve destek sayfası — App Store blokeri

- [ ] **Kullanım Şartları sayfası YOK** — `rotori-website/`'da yalnız
      `privacy-tr/en`, `destek-tr`, `support-en` var. Abonelik için
      oluşturulmalı (TR + EN)
- [ ] `rotori-website/destek-tr.html:63` hâlâ *"Rotori şu an tamamen
      ücretsizdir. Reklam yok, abonelik yok, uygulama içi satın alma yok"*
      diyor → güncellenir (`support-en.html` de)
- [ ] Privacy Policy'ye eklenir: satın alma işlem kimlikleri, abonelik
      statüsü, saklama süresi, Apple ↔ Supabase veri akışı
- [ ] Hesap silme ekranına §8b.9 uyarısı + "Aboneliği yönet" bağlantısı

### 9. App Store Connect yapılandırması (kullanıcı)

- [ ] Production **ve** sandbox S2S bildirim URL'leri
- [ ] App Store Server API: anahtar, issuer ID, key ID + rotasyon görevi
- [ ] Subscription group içinde aylık/yıllık **seviye sırası** ve
      upgrade/downgrade davranışı tanımlanır

### Faz 1 sonrası (aynı branch'te devam)

6. **Faz 2** — paywall ekranı (iki SKU, yıllık varsayılan + "en avantajlı",
   deneme yalnız yıllıkta), Apple abonelik açıklama maddeleri, restore butonu,
   ToS/Privacy linkleri, `l10n.dart:2646` "sunulacak" kopyasının değişmesi,
   **rota optimizasyonu AI çağrısının Edge Function'a taşınması** (şu an kilit
   `plan_viewer_screen.dart:4055`'te istemcide, prefs ile aşılabilir)
7. **Faz 3** — ön izleme hunisi (ilk oturumda tamamlanmalı: denemelerin %82'si
   kurulum günü başlıyor), "kazandırdığı saat" göstergesi
   (`plan_optimization_controller.dart:44` `totalTravelMinutes` farkı —
   **fallback yolundan gelen sonuçta gösterilmez**), gezi limiti 1 aktif
8. **Faz 4** — `rotori-mobile/docs/IOS_RELEASE_MANUAL_GATE_CHECKLIST.md`
   baştan sona (şu an tek kutu işaretli değil — **gerçek kritik yol bu**)

## Şu An Değişen Dosyalar

Çalışma dizini aktiftir ve birden fazla iş paketi commit'lenmeden birlikte
durmaktadır: rota/biletli aktivite geliştirmeleri, deneyim rehberi +
hatırlatıcılar + Keşfet tasarımı ve `rotori-social/` otomasyon değişiklikleri.
`.claude/launch.json` ile `rotori-social/data/*` çalışma-zamanı/yerel durum
dosyaları kullanıcıya aittir; mobil özellik işi bu dosyaları değiştirmez veya
geri almaz. Checkpoint alınırken kapsam dosya bazında açıkça ayrılmalıdır.

## 2026-08-11 — Premium Japonca çevrimdışı metin çevirisi

- [x] Japonca sekmesine TR/EN ↔ JA cihaz-üstü metin çeviri kartı eklendi.
- [x] İlk kullanımda iki ML Kit dil paketini indiren, sonrasında çevrimdışı
      çalışan model yönetimi eklendi.
- [x] Mikrofonlu konuşma modu, konuşma izinleri ve runtime ses bağımlılıkları
      App Store sürümünden kaldırıldı; aşağıdaki hazır ifade sesleri yerel MP3
      asset'leriyle çalışmaya devam ediyor.
- [x] Çevirmen `premiumProvider` kaynağına bağlandı. Ücretsiz kullanıcıda en
      üstte kilitli premium kartı görünür; premium açılınca metin alanı ve model
      indirme akışı otomatik açılır.
- [x] Google Translate sonuç atfı ve otomatik çeviri doğruluk uyarısı eklendi.
- [x] TR/EN gizlilik politikası yalnız cihaz-üstü metin çevirisini anlatacak
      şekilde güncellendi; App Store inceleme notu ve QA matrisi sadeleştirildi.
- [x] Web conditional stub ile derleme korunuyor; mobil-only aksiyonlar ön
      izlemede açıklamalı olarak pasif.
- [x] Eksik `/price-tag-scanner` ve `/live-currency-scanner` preview rotaları
      eklendi; fiyat etiketi tarama sayfası görsel QA'da açıldı.
- [x] Premium kilitte model kontrolünün başlamadığı ve premium metin çevirisinin
      çalıştığı widget testleri eklendi.
- [ ] Gerçek iPhone'da dil paketlerini indirip uçak modunda iki yönlü metin
      çevirisi tamamlanacak. 11 Ağustos denemesinde debug build ve Apple
      imzalama tamamlandı; iOS 27 cihazına yükleme Xcode 26.6'nın developer disk
      image'ı bağlayamaması nedeniyle durdu. Uyumlu Xcode/device support ile
      yeniden denenmeli.
- [ ] Android debug APK kontrolü CameraX/Gradle hattındaki mevcut
      `CallbackToFutureAdapter` compile-classpath hatasında durdu; ses katmanı
      öncesindeki bu bağımlılık uyumsuzluğu ayrı Android build işi olarak
      çözülmeli.

## 2026-08-11 — Günlük geçişleri kompaktlaştırma

- [x] Günlük akıştaki büyük yürüyüş/ulaşım kartları ikon, duraklar, tür ve
      süreyi taşıyan tek satırlık kompakt satırlara çevrildi.
- [x] Kullanıcı optimizasyon çalıştırmadan önce de başlangıç, duraklar arası ve
      güne dönüş geçişleri mevcut sıra üzerinde `TAHMİNİ` olarak gösteriliyor.
- [x] Onaylanmış rota snapshot'ı varsa tahmini satırlar yerine kaydedilmiş
      gerçek/tahmini ayaklar aynı kompakt sunumla kullanılıyor.
- [x] İlk plan üretiminin yerel kural/katalog tabanlı, tam rota
      optimizasyonunun ise ayrı beam-search + validator hattı olduğu ürün
      sözleşmesinde açıkça ayrıldı.
- [ ] Flutter SDK önbelleği proje yazma alanının dışında kaldığı ve bu oturumun
      dış izin kotası dolduğu için son iki dosyanın analyze/widget test tekrarı
      bir sonraki izinli çalıştırmada yapılacak. Bu değişiklikten önceki hedefli
      rota/hatırlatıcı testleri 46/46, Eats/diyet testleri 45/45 ve çevirmen
      testleri 5/5 geçmiştir.

## Son Commit'ler (referans)

```
4578280 feat(website): baştan aşağı revizyon — Design System v2
70c82d2 fix(test): plan_viewer + day_map regresyonlarını çöz — F2.0
cbd592a copy(website): 'Hesap gerekmez' → 'Ücretsiz · reklamsız'
08d7449 feat(website): Privacy Policy + Destek sayfaları + footer link
11f3541 feat(release+web): F1 App Store prep — Info.plist, hesap silme
```
