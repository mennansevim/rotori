# DECISIONS.md — Mühendislik Karar Log'u

> **Append-only.** Eski kayıtlar silinmez. Her önemli mimari veya iş kuralı kararı buraya girer.
> Yeni kayıt en **üste** eklenir (ters kronolojik). Şablon en altta.

---

## Karar 17 — 2026-08-11
### Karar
Hiçbir görsel arama sorgusu ham hâlde Unsplash'e gitmez. Sorgu üç adımdan geçer
(marka → çekilebilir sahne, Türkçe → İngilizce, Japonya çıpası) ve az sonuçta
daha genel sahnelerle **biriktirerek** tamamlanır. Kural tek yerde
(`downloader.enrich_query`) yaşar; hem manuel arama hem otomasyon onu kullanır.

### Neden
Kullanıcı "teamlabs yazınca saçmalıyor" dedi; gerçek ölçüm doğruladı:
`teamlabs` → 3 alakasız sonuç (saat kulesi, portre), `immersive digital art
installation japan` → 2068 ilgili sonuç. Sebep: stok fotoğraf arşivinde
marka/tesis adı yoktur. Ayrıca arayüz Türkçe olduğu için kullanıcı "tapınak
bahçesi" yazıyor, Unsplash İngilizce arıyor.

Bu bir regresyon DEĞİLDİ: eski `studio.html` da aynı endpoint'e ham sorgu
gönderiyordu ve `downloader.py` geçmişinde zenginleştirme hiç olmamıştı.
"Eskiden iyiydi" hissi otomasyon yolundan geliyordu — orada editöryel model
zaten marka adı yasaklı bir `gorsel_konsepti` üretiyor. Yani zekâ vardı ama
yalnızca LLM'in geçtiği yolda; kullanıcının elle yazdığı yolda yoktu.

### Değerlendirilen alternatifler
1. **Her aramada LLM'e sorgu çevirtmek** — reddedildi: her tuşa basışta gecikme
   ve OpenAI maliyeti; arama anlık olmalı. (LLM zaten otomasyon yolunda var.)
2. **Kullanıcıyı eğitmek (placeholder'da "İngilizce genel sahne yaz")** — reddedildi:
   arayüz Türkçe, kullanıcı Türkçe yazacak; sorunu kullanıcıya devretmek olur.
3. **Deterministik eşleme + çıpa + kademeli fallback** — kabul: anlık, ücretsiz,
   test edilebilir, davranışı öngörülebilir. Eksik marka olursa fallback yine
   makul sonuç verir. (**Kabul**)

### Ödünler
- **Yararı**: manuel arama otomasyon kadar isabetli; Türkçe yazan kullanıcı
  İngilizce arşivden sonuç alır; boş/az sonuçlu grid biter.
- **Maliyet**: marka listesi elle bakım gerektirir (eksik marka fallback'e düşer,
  sessiz başarısızlık değil). Az sonuçlu sorgularda 1 yerine en fazla 3 Unsplash
  isteği — 50/saat kotası için kasıtlı üst sınır.

### Sonuçları
- `downloader.py`: `enrich_query`, `build_search_queries`, `search_with_fallback`
  + `_BRAND_SCENES` / `_TR_EN` / `_JP_ANCHORS` tabloları.
- `POST /api/backgrounds/preview` yanıtı `effective_query` + `tried` ile genişledi
  (additive — mevcut alanlar korundu).
- Dashboard `picker-query-note` şeridi çeviriyi kullanıcıya gösterir; sorgu
  gizli bir sihir değil, denetlenebilir bir adım.
- `news_automation._pick_image` ad-hoc kademesini bıraktı, ortak yardımcıya geçti.
- `tests/test_image_search_enrichment.py` — 36 test (marka eşlemesi, Türkçe ek
  çevirisi, çıpa, kademe, kota sınırı, ağ hatası davranışı).

---

## Karar 16 — 2026-08-10
### Karar
Toplu üretimde tek turun hatası bulk'u çökertmez; konu havuzu tükendiğinde
konular **sessizce yeniden açılmaz** (cooldown, varsayılan 45 gün); dedup aynı
konuyu farklı kaynaktan da yakalar. Konu havuzu ulaşım / konaklama / tema parkı
/ pratik kural başlıklarıyla 25'ten 57'ye çıkarıldı.

### Neden
Kullanıcı iki somut arıza bildirdi ve ikisi de kanıtlandı:

1. **"10 haber üret hata veriyor ama arkada 6-7 tane oluşturmuş."**
   `_run_now_bulk` her turu `run_once` çağrısıyla çalıştırıyor ama exception
   yakalamıyordu. `run_once` görsel bulamayınca `RuntimeError` atıyor (Unsplash
   free tier saatlik 50 istek limiti 10 turluk bulk'ta rahatça dolar) →
   `JobManager._run_callable` işi "hata" olarak kapatıyor, o ana kadar üretilmiş
   kartlar sessizce kalıyordu.
2. **"Daha önce oluşturduğu konuları tekrar tekrar oluşturuyor."**
   `news_automation.run_once` içinde `if not fresh_topics: fresh_topics = list(pool)`
   satırı, havuz tükendiğinde TÜM havuzu geri açıyordu. Canlı state kanıtı:
   25 konuluk havuzda taze konu **0**; Pi history'sinde 56 kayıttan 16'sı tekrar
   (Kar Mevsimi 4x, Sakura Zamanı 4x, Sonbahar Yaprakları 4x, Fushimi Inari 3x).
   `topic_automation._pick_topic` içinde de aynı satır vardı.

Ek olarak dedup yalnız RSS linkine bakıyordu; aynı başlık başka bir feed'den
gelirse yeni sayılıyordu. `used_ids` de `list(set)[-CAP:]` ile yazıldığı için
"en yeniyi tut" garantisi yoktu.

### Değerlendirilen alternatifler
1. **Havuzu sıfırlamaya devam et, sadece havuzu büyüt** — reddedildi: tekrar
   ertelenir, çözülmez; havuz yine tükenir.
2. **Bir konu bir kez üretilir, asla tekrar etmez** — reddedildi: evergreen
   konular kalıcı olarak yanar, havuz uzun vadede kuruyup slot boş kalır.
3. **Cooldown: N gün geçmeden tekrar yok, sonra en eski önce** — kabul: hem
   yakın tekrar biter hem havuz uzun vadede yaşar. Havuz tükenip cooldown da
   dolmadıysa evergreen fazı açık uyarıyla atlanır — sessiz tekrar yerine
   görünür bir "yeni konu ekle" sinyali. (**Kabul**)

### Ödünler
- **Yararı**: tekrar biter; bulk kısmi hatada 6 kartı kaybetmez; atlama nedenleri
  panelde okunur (`topic` ve `downloader` logger'ları da canlı akışa bağlandı).
- **Maliyet**: kayıt başına 4 dedup anahtarı → state dosyası büyür (`_USED_CAP`
  200→800). Cooldown, havuz küçükken üretimi durdurabilir; bu bilinçli bir
  ödün — sessiz tekrar yerine görünür duruş.

### Sonuçları
- `news_automation`: `_dedup_keys` / `_is_used` / `_remember` / `_ordered_used` /
  `_norm_title` / `eligible_topics` eklendi. Görsel bulunamaması artık
  `reason="no_image"` sonucudur, exception değil.
- `topic_automation._pick_topic` ortak `eligible_topics`'i kullanır; state yazımı
  ortak anahtar şemasına geçti. Eski state dosyaları geçersiz olmadı (iki eski
  hash şeması da anahtar setinde).
- `config.yaml.example` → `news_automation.topic_cooldown_days: 45`
  (env: `NEWS_TOPIC_COOLDOWN_DAYS`).
- `assets/topic_pool.json` 57 konu. Marka adı içeren Unsplash sorgusu testle
  yasak — mevcut "stok fotoğrafta bulunmalı" kuralıyla tutarlı.
- RSS seçim prompt'una ulaşım/konaklama/tema parkı/ziyaretçi kuralları öncelikleri
  eklendi.
- `tests/test_automation_dedup_and_bulk.py` — 15 test bu üç davranışı kilitler.

---

## Karar 15 — 2026-08-10
### Karar
Otomasyon ekranındaki `Yayın Akışı` / `Yayın Düzeni` sekme ayrımı kaldırıldı.
Her akışın yayın düzeni (gün, saat, otomatik yayın) artık **kendi akış kartının
üstünde** durur ve akış kart başlığındaki **aç/kapat anahtarıyla** yönetilir.
Kapalı akış ekrandan kaybolmaz. Yayınlanmış içerikler akış kartlarının altında
salt okunur **Yayın Geçmişi** bloğunda listelenir.

### Neden
Kullanıcı bir akışın kadansını değiştirmek için ekranın bağlamını bırakıp ayrı
bir sekmeye gidiyor, orada iki slot kartını birbirinden ayırt etmek zorunda
kalıyordu. Düzen ile onu etkileyen slot listesi aynı ekranda olmadığı için
"hangi ayar hangi akışı vuruyor" ilişkisi görünmüyordu. Ayrıca kapalı akış
listeden tamamen düşünce, akışı açmanın yolu ekranda kalmıyordu.

### Değerlendirilen alternatifler
1. **Sekmeyi koru, sadece etiketleri iyileştir** — reddedildi: bağlam kopukluğu
   duruyor, düzen hâlâ slot listesinden uzakta.
2. **Düzeni modalda aç (kart üstünde "Düzenle" düğmesi)** — reddedildi: kadans
   bir kez ayarlanıp uzun süre bakılan bir bilgi; modal onu gizler ve akış
   başlığındaki kadans rozetiyle çakışır.
3. **Düzen şeridini akış kartının içine, slotların üstüne yerleştir** — kabul:
   ayar, etkisi ve etkilenen içerik tek göz taramasında görünür. (**Kabul**)

### Ödünler
- **Yararı**: tek ekran; kapalı akış da yönetilebilir; global "Ayarları Kaydet"
  düğmesi yerine lane başına kaydetme, yanlış lane'i kaydetme riskini bitirir.
- **Maliyet**: akış kartı uzadı (mobilde düzen şeridi dikey yığılır); düzen
  girdileri artık 30 saniyelik otomatik yenilemenin çalıştığı panelin içinde
  yaşıyor, bu yüzden yenileme için "kirli/odaklı" koruması eklemek gerekti.

### Sonuçları
- `pages/automation.js`: `automation-tabs` ve `renderSettingsPanel` kaldırıldı;
  yerine `laneConfigStrip` / `saveLane` / `toggleLane` / `renderHistoryPanel`.
- Kaydetme lane bazlı: `POST /api/automation/config` gövdesinde yalnız
  `news` **veya** `topic` gider. Endpoint sözleşmesi değişmedi.
- Akışı kapatmak o lane'in planlı içeriklerini iptal ettiği için kapatma, etkilenen
  içerik sayısını söyleyen açık bir onay modalı ister. Haber akışı için gün
  seçilmemişse açma denemesi 422 beklemeden istemcide uyarır.
- Otomatik yenileme kaydedilmemiş düzeni ezmez (`anyLaneDirty` + odak kontrolü).
- Dashboard modülleri `20260810-7` cache anahtarını birlikte kullanır.

---

## Karar 14 — 2026-08-10
### Karar
Modüler Social dashboard teknik Otomasyon ekranından değil, karar odaklı
**Genel Bakış** ekranından açılır. Ana bilgi mimarisi tamamen Türkçedir:
`Genel Bakış / Kütüphane / Otomasyon / Aktivite / Ayarlar`. Genel Bakış
salt-okunur kalır; anında yayınlama, yeniden deneme ve bağlantı kesme eylemleri
ikinci bir açık kullanıcı onayı ister.

### Neden
Demo kullanıcı ilk açılışta haftalık slot, anchor ve queue gibi sistem
kavramlarıyla karşılaşıyordu. İngilizce etiketler, kaydedilmeyen Ayarlar
seçimleri ve ham hata mesajları kullanıcıya sistem bakım paneli hissi veriyordu.
Etkili yayın eylemlerinin tek tıkla çalışması da yanlış gönderim riskini
artırıyordu.

### Sonuçları
- İlk ekran bugünün kararlarını, üç aşamalı içerik yaşam döngüsünü, sıradaki
  yayını ve dikkat gereken işleri özetler.
- Kaydedilmeyen arayüz kontrolleri gösterilmez; gerçek ayar yüzeyine bağlantı
  verilir.
- Teknik hata metni kaybolmaz fakat varsayılan görünümde kullanıcı diline
  çevrilir ve isteğe bağlı ayrıntı altında tutulur.
- Dashboard modülleri `20260810-6` cache anahtarını birlikte kullanır.

---

## Karar 13 — 2026-08-10
### Karar
Kütüphane içerik yaşam döngüsü yalnız üç ana aşamadan oluşur:
**Taslak → Onaylandı → Yayınlandı**. Otomasyon bir ana aşama değildir;
Onaylandı içeriğinin planlama alt durumudur. Tek karttaki otomasyon eylemi
yalnız o kartı, toplu eylem ise tüm uygun onaylı kartları planlar.

### Neden
Kullanıcının temel kararları içeriği incelemek, onaylamak ve yayın sonucunu
görmektir. `Sırada` veya `Otomasyonda` gibi teknik durumları aynı seviyede
göstermek ürün akışını gereksiz yere dört-beş aşamaya bölüyordu. Ayrıca önceki
tekli kart eylemi toplu endpoint'i çağırdığı için kullanıcının seçmediği diğer
onaylı içerikleri de planlayabiliyordu.

### Sonuçları
- Taslak onaylanınca Onaylandı görünümüne geçer.
- Onaylandı kartı otomasyona eklenince aynı görünümde kalır ve planlanan zamanı
  `Otomasyonda` alt durumuyla gösterir.
- Upload logu yayın sonucunu doğruladığında kart Yayınlandı arşivine geçer.
- Tekli ve toplu otomasyon eylemlerinin API sözleşmeleri ayrıdır.

---

## Karar 12 — 2026-08-10
### Karar
Her Social deploy'u UTC zaman damgalı benzersiz bir `DEPLOY_ID` üretir. Bu
kimlik Docker imajındaki `BUILD_INFO` dosyasına yazılır ve `/api/version`
yanıtında SemVer build metadata olarak gösterilir. Dashboard statik dosyaları
`no-cache, no-store, must-revalidate` ile sunulur.

### Neden
Aynı commit yeniden deploy edildiğinde önceki commit tarihi değişmediği için
canlı sürümü ayırt etmek mümkün değildi. Sabit statik dosya URL'leri de eski
tarayıcı/CDN cache'inin yeni arayüzü gölgelemesine izin veriyordu.

### Sonuçları
- Her deploy dışarıdan benzersiz bir sürümle doğrulanabilir.
- `commit: unknown` yalnız deploy scripti atlanırsa görülebilir; normal deploy
  gerçek commit ve deploy zamanını taşır.
- Dashboard kodu yeni deploy sonrasında zorunlu olarak yeniden doğrulanır.

---

## Karar 11 — 2026-08-10
### Karar
Mavi haber otomasyonu tek bir haftalık günle sınırlandı. Güncel kadans
Çarşamba 23:21'dir. Dashboard canlı sırası yalnız aktif kuyruk durumlarını
(`pending`, `ready`, `uploading`) gösterir; başarısız ve iptal edilmiş kayıtlar
yalnız yayın logunda tutulur.

### Neden
- Birden fazla haber günü seçilebildiği için sıra haftada iki kez ilerliyordu;
  ürün beklentisi haber hattında haftada bir yayındır.
- Geçmiş başarısız kayıtlar aktif sıraya ve canlı anchor seçimine dahil olduğu
  için ekran geçmiş bir kartta takılı görünebiliyordu.
- On dört günlük görünüm, haftalık kadansta beş kartlık sıranın çoğunu gizliyordu.

### Sonuçları
- Haber gün seçici radio gibi davranır ve aktif haber otomasyonu API katmanında
  tam bir gün gerektirir.
- İlk beş aktif içerik tarih sırasıyla gösterilir; daha ileridekiler bekleyen
  adet olarak özetlenir.
- Mevcut hata geçmişi silinmez; operasyonel inceleme için loglarda kalır.

---

## Karar 10 — 2026-07-30
### Kararı
`japonya-ruyasi-dashboard-design.zip` paketindeki editöryel dashboard tasarımı üretim kalitesinde uygulandı. Yeni tek dosyalı SPA (`src/web/static/studio.html`) `?ui=new` feature flag'i ve `/studio` route'u ile mevcut arayüzün yanında yayınlandı; eski `index.html` bozulmadan `/` kök adresinde default olarak kaldı.

### Neden
- Prompt açıkça: "Görsel dili, sayfa hiyerarşisini, metinleri, spacing sistemini ve responsive davranışı koru; ancak projenin mevcut teknoloji yığınını ve API sözleşmelerini değiştirme."
- Tasarım kağıt beyaz zeminli editöryel bir "içerik stüdyosu" hissi veriyor; mevcut arayüz operasyon paneline yakın. İkisi aynı anda çalışırsa (feature flag) risk azalır ve kullanıcı iki deneyimi kıyaslayabilir.
- 7 ekran (Genel Bakış / AI Stüdyo / Takvim / Kütüphane / Yayın Kuyruğu / Analiz / Ayarlar) mevcut 66 endpoint üzerinde çalışabiliyordu; yeni endpoint gerekmedi.

### Değerlendirilen alternatifler
1. **Eski `index.html`'yi tamamen değiştir** — Reddedildi: 5.5k satırlık mevcut UI'ın onlarca kenar davranışı test edilmemişti; feature flag olmadan geri dönüş yolu yok.
2. **React/Vue ile bileşenlere ayır** — Reddedildi: build tool'u yok, deploy Pi5 üzerinde Docker + statik dosya. Yeni bir toolchain deploy pipeline'ını değiştirir.
3. **Tek dosyalı yeni SPA + feature flag** — **Kabul**: proje konvansiyonuyla uyumlu (tek dosyalı frontend, `docs/CLAUDE.md §8-5`), eskisiyle paralel yaşayabilir, migration risk'i minimum.

### Ödünler
- **Yararı**: Aynı endpoint'ler; yeni arayüz `/studio` veya `?ui=new` ile hemen kullanılabilir; hata çıkarsa `/` üzerindeki eski UI kırılmadan durur. Görsel dil (paper #F2EFE7, mercan kırmızısı #E34332, Georgia display + Inter sans, 18-20px radius, 300%×200% editorial atlas) prototipe sadık kaldı.
- **Maliyet**: İki UI dosyası paralel bakım gerektirir. Yeni UI 100% JS render; eski UI'daki bazı ince operasyon davranışları (canlı log akışı footer, widget aç butonu vb.) henüz yeni arayüzde yok — süreç iş için hâlâ eski UI'ya gitmek gerekiyor.
- **Ek maliyet**: `japan-editorial-grid.png` (2.5MB) statik olarak sunuluyor; ilk yüklemede genel arayüz +2.5MB alıyor. HTTP cache'lenir; sonraki ziyaretlerde ücretsiz.

### Sonuçları
- Yeni endpoint: `GET /studio`. Yeni davranış: `GET /?ui=new` veya `?ui=studio` → studio.html.
- `src/web/static/studio.html` içindeki `apiFetch` helper'ı `docs/DECISIONS.md — Karar 7`'daki HTTP katmanının aynısını tekrar uygular; timeout + AbortController + `ApiError` sınıfı.
- Bileşen ↔ endpoint eşlemesinin tamamı `docs/CURRENT_TASK.md`'de tabloda listelenmiştir.
- **Sıradaki iterasyon**: kullanıcı doğrulaması sonrası `/` default'ını yeniye çevir (Karar 11 adayı). Ayrıca canlı log footer'ı yeni UI'ya taşı; takvim sürükle-bırak; scheduler config toggle için config.yaml write endpoint'i (şu an sadece okuma).

---

## Karar 9 — 2026-07-30
### Kararı
Web arayüzünün ana bilgi mimarisi teknik modül adlarından kullanıcı iş akışına çevrildi: `Bugün → Hazırlık → Yayına Hazır → Otomasyon`; mevcut üretim ve yayın endpoint'leri değiştirilmedi.

### Neden
- Önceki sidebar aynı işi farklı adlarla tekrar eden yedi hedef gösteriyordu (`Üretilen Kartlar`, `Yayın Kuyruğu`, `Otomasyon`, `Kaynaklar`, `Ayarlar`); kullanıcı içerik durumunu değil sistem modüllerini öğrenmek zorunda kalıyordu.
- Ürünün gerçek işi üç karar etrafında dönüyor: içerik hazırla, kontrol et, yayın planına al.
- Buffer, Later, Metricool ve Hootsuite gibi yayın araçlarında ortak desen taslak/kütüphane, onay ve planlama durumlarının ayrı ve görünür olması.

### Değerlendirilen alternatifler
1. **Yalnız görsel makyaj** — Reddedildi: karmaşıklığın kaynağı renkler değil, aynı seviyedeki fazla menü hedefiydi.
2. **Yeni backend dashboard endpoint'leri** — Reddedildi: mevcut endpoint'ler gerekli veriyi sağlıyor; haber üretme mekaniğine risk eklerdi.
3. **Frontend görünüm katmanı** — **Kabul edildi**: `openWorkspace(view)` mevcut panelleri iş adımlarına ayırır, API sözleşmeleri ve üretim fonksiyonları korunur.

### Ödünler
- **Yararı**: Masaüstünde beş, mobilde dört açık hedef; hazırlık, onay ve otomasyon birbirine karışmıyor.
- **Maliyet**: `panel-cards` fiziksel olarak tek DOM olmaya devam ediyor ve `data-workspace-view` ile üç sunum moduna ayrılıyor. Tam bileşen ayrıştırma ileri bir refactor konusu.

### Sonuçları
- Haber, konu ve görsel üretme fonksiyonları aynen çağrılır; yalnız giriş noktaları ve metinleri sadeleşti.
- Eski `sideNav` çağrıları geriye uyumluluk sarmalayıcısı olarak korunur.
- Onay sayısı hem Bugün ekranında hem sidebar rozetinde görünür; boş onay kuyruğunda açıklayıcı boş durum gösterilir.

---

## Karar 8 — 2026-07-30
### Kararı
"🏠 Bugün" paneli varsayılan başlangıç ekranı olarak eklendi. Mevcut "Kartlar / Reels / Büyüme" tab'ları KALDIRILMADI; Bugün onların önüne 4. tab olarak konuldu ve sayfa açılışında default görünür.

### Neden
- Prompt'un açıkça talep ettiği başarı ölçütü: "Kullanıcı uygulamayı açtığında birkaç saniyede *bugün ne yapmalıyım / hangi içerik onay bekliyor / sırada ne yayınlanacak* sorularını görebilmeli."
- Mevcut arayüz "üretim ağırlıklı" — operasyon durumu farklı sayfalara dağılmış (analytics büyüme'de, kuyruk büyüme'de, onaylar kartlar'da, iş durumu footer'da).
- Tek bir "kokpit" ekranı bu bilgi mimarisi problemini çözer.

### Değerlendirilen alternatifler
1. **Yeni endpoint `/api/dashboard/today`** — tek round-trip. Reddedildi: 7 endpoint zaten var, `Promise.allSettled` ile paralel çağırmak Pi5'te yeterli, backend'i şişirmeye gerek yok.
2. **Sidebar'a "Bugün" öğesi ekle, tab değil** — Reddedildi: tab yapısına uyumlu olmak `switchTab` konvansiyonunu koruyor.
3. **"Bugün" tab'ı 4. konumda, default açık** — **Kabul edildi**. Sidebar'daki "🏠 Ana Sayfa" zaten `home:"today"` map'ler.

### Ödünler
- **Yararı**: 4 durum kartı + 5 hızlı eylem + son 8 içerik = tek ekranda operasyon özeti. Kullanıcı ~3 saniyede günlük durumu okuyor.
- **Maliyet**: Sayfa yüklenirken 7 paralel fetch — mobilde ilk paint gecikebilir (~200-300ms) ama loading skeleton'u durumu yumuşatıyor. Her fetch 5s timeout'lu; biri düşerse ilgili kart `err` renginde kalıyor.

### Sonuçları
- Kullanıcı önce "Kartlar" görürken şimdi "Bugün" görüyor — davranış değişikliği.
- Yeni bileşen desenleri: `.today-quick-btn`, `.today-stat`, `.today-recent-item` — sonraki iterasyonlarda `components/` klasörüne çıkarılacak.
- İleride: takvim görünümü, sürükle-bırak yeniden planlama, "aynı gün mükerrer içerik" uyarısı bu ekrana entegre edilebilir.

---

## Karar 7 — 2026-07-30
### Kararı
Frontend'e ortak bir `apiFetch(url, opts)` HTTP katmanı + `ApiError` sınıfı eklendi. Yeni kod ham `fetch()` yerine bunu kullanır; mevcut ~40+ `fetch(...)` kademeli olarak geçirilecek.

### Neden
- Repo'da ~40 farklı `fetch()` çağrısı var; timeout, abort, hata mesaj normalizasyonu her yerde el yordamı. Kimi yerlerde `.catch(e => {})` var — sessiz hata.
- 3rd party servisler (Ollama, OpenAI, Instagram Graph) zaman zaman geç yanıt veriyor; timeout yok = kullanıcı arayüzü donuk kalıyor.
- Hata gösterimi tutarsız: bazı yerlerde `r.statusText`, bazı yerlerde `j.detail`, bazı yerlerde toast bile yok.

### Değerlendirilen alternatifler
1. **`axios` bağımlılığı eklemek** — Reddedildi: prod bundle'a extra ~15KB, offline destek yok, native fetch yeterli.
2. **Her fetch'i tek tek düzeltmek** — Reddedildi: bakım maliyeti yüksek.
3. **Global `apiFetch` helper** — **Kabul edildi**: opt-in, geriye uyumlu, yeni kod bundan başlar.

### Ödünler
- **Yararı**: yeni kod tek satır — `await apiFetch("/api/x", {json: body, timeout: 60000})`. `ApiError` yakalanır, `e.status` + `e.detail` kullanıma hazır.
- **Maliyet**: Mevcut ~40 fetch çağrısı hâlâ ham. Migration istekli. Zamanla ısınacak.

### Sonuçları
- "Bugün" paneli tamamen `apiFetch` kullanır — canlı doğrulama yaptı (runtime test: 404 endpoint için `{status:404, msg:"Not found"}` normalizasyonu doğru).
- Bir sonraki refactor pass'te `withLoading + apiFetch` kombinasyonu default pattern olarak `docs/CLAUDE.md §9`'a girecek.
- İleride: request tracing (`X-Request-ID`), retry policy (idempotent endpoint'ler için) buradan eklenebilir.

---

## Karar 6 — 2026-07-30
### Kararı
`src/web/app.py`'nin 2584 satırlık monolitik yapısı **strangler pattern** ile aşamalı olarak router paketine bölünür. İlk adım: `src/web/routers/system.py` (3 route — `/api/version`, `/api/status`, `/api/logs`).

### Neden
- 2584 satırlık tek dosya değişiklik hızını yavaşlatıyor; her PR conflict riski taşıyor.
- Test yazmak zor — tek `app.py` import edildiğinde tüm side-effect'ler (cfg load, JobManager, staticfiles mount) tetikleniyor.
- Domain sınırları zaten yorum bloklarında çizili (Meta, Reels, Story, Scheduler...) — sadece dosyalara taşıma gerekli.

### Değerlendirilen alternatifler
1. **Tek büyük refactor** — Reddedildi: 66 route tek PR'da risk yüksek, code review imkansız.
2. **Router'ları dependency-injection ile bağla** — FastAPI `Depends`. Reddedildi: mevcut singleton pattern (module-level `cfg`, `manager`) çalışıyor; yalnızca dosya bölmesi hedef; DI ileri iterasyonda.
3. **`src/web/routers/` altında domain başına dosya** — **Kabul edildi**. Router'lar `src/web/dependencies.py` üzerinden singleton'a erişir.

### Ödünler
- **Yararı**: her router'ı bağımsız test edebiliyoruz; contract test her taşıma öncesi yazılır ve sözleşmeyi kilitler.
- **Maliyet**: iki API sürümü yan yana kısa süre yaşayabilir (biri router, biri app.py). Ancak sözleşme aynı olduğu için tüketici fark hissetmez.
- **Ek maliyet**: `_read_version` eskiden module-load'da 1 kez cache'lenirdi; şimdi her `/api/version` çağrısında hesaplanır (git subprocess ~50ms). Deploy sonrası VERSION güncel görünmesi için bu istendi zaten; performans etkisi ihmal edilebilir ama LRU cache eklenebilir.

### Sonuçları
- `src/web/dependencies.py` — router'ların singleton bridge'i (`set_runtime`, `get_cfg`, `get_manager`).
- `tests/test_contracts_system.py` — 6 test, sözleşme kilidi.
- Sıradaki router split hedefleri: `scheduler.py` (4 route), `analytics.py` (4 route), `stories.py` (12 route), `reels.py` (6 route), `approvals.py` (5 route), `automation.py` (4 route), `publishing.py` (Instagram + TikTok 10 route).

---

## Karar 5 — 2026-07-30
### Kararı
Kalıcı proje belleği `docs/` altında 4 dosya olarak yapılandırıldı: `CLAUDE.md`, `ARCHITECTURE.md`, `CURRENT_TASK.md`, `DECISIONS.md`. Kod yazmadan önce her oturumda okunur.

### Neden
- Proje 10.6k satır Python + 4.7k satır frontend'e ulaştı; bilgi tek insan zihninde kaybolabilir.
- Yeni Claude oturumları geçmiş context'i devralamıyor — dokümantasyon single source of truth olmalı.
- Onboard süresini (yeni ekip üyesi veya 6 ay sonraki kendisi) azaltmak için birebir güncel mimari şart.

### Değerlendirilen alternatifler
1. **Tek `docs/PROJECT.md`** — kısa vadede kolay, uzun vadede iç içe. Reddedildi: bakım zor.
2. **`README.md`'yi büyütmek** — dış kullanıcıya çokça iç bilgi sızar. Reddedildi: hedef kitle farklı.
3. **Yalnızca `CLAUDE.md`** — 4 dosya bölünmesi kabul edilebilir ama "hangi bilgi nerede" belirsizleşir. **Kabul edilen**: 4 dosya, her birinin dar sorumluluğu var (`CLAUDE`=nadir değişen, `ARCHITECTURE`=akış, `CURRENT_TASK`=bugün, `DECISIONS`=append-only tarih).

### Ödünler
- **Yararı**: her yeni özellik öncesi bilgi katmanı hazır; kararlar tarihe bağlı, geriye dönük denetlenebilir.
- **Maliyet**: her PR'da dokümantasyonu güncelleme disiplini gerekir; unutulursa doküman stale olur ve güven kaybeder.

### Sonuçları
- Repo root'a hiçbir yeni doküman eklenmez; hepsi `docs/`'a.
- Her feature PR'ı Definition of Done'da (`CLAUDE.md §16`) belirtilen 8 maddeyi karşılamalı.
- CI'de doküman lint yok — disiplin sorumlusu insan. Yakında `pre-commit` hook düşünülebilir.

---

## Karar 4 — 2026-07-30
### Kararı
Web arayüzünde "çalışmayan buton" tespitine karşı 3 sistemik iyileştirme uygulandı:
1. Global `.is-loading` CSS sınıfı + `withLoading(btn, fn)` JS helper — herhangi bir butonu spinner'a çevirir.
2. Global `button:focus-visible` outline (a11y).
3. Config eksik durumlarında ilgili buton **upfront disable** — endpoint çağırıp toast'la başarısız olmak yerine.

### Neden
- 57 farklı onclick handler'ı statik olarak tanımlıydı ama runtime davranışı belirsizdi:
  - Yenile butonları görsel feedback vermiyordu → kullanıcı "donmuş" hissediyordu ve çift tıklıyordu (çift request).
  - `.acct-btn` gibi bazı stiller hover/focus yoksaymıştı — sadece statik gradient.
  - Instagram/TikTok config eksikken bazı butonlar aktifti, tıklayınca 400 döndürüyordu.

### Değerlendirilen alternatifler
1. **Her butonu tek tek düzeltmek** — bakım maliyeti yüksek, yeni butonda tekrar yaşanır. Reddedildi.
2. **`fetch` interceptor** — tüm fetch'leri sarıp buton'u bulmak — DOM ↔ istek eşlemesi zor. Reddedildi.
3. **`withLoading` helper** — çağıran bilinçli "bu buton uzun sürer" der. **Kabul edildi**: minimum sürtünme, opt-in.

### Ödünler
- **Yararı**: yeni butonlar için tek satır `onclick="withLoading(this, fn)"` yeterli.
- **Maliyet**: helper unutulursa buton yine "donuk" görünür — konvansiyon zorunluluğu.

### Sonuçları
- Frontend'de artık "buton spinner" için tek konvansiyon: `withLoading(btn, asyncFn)`.
- Kısaltma yaklaşımı devreye alınabilir — ileride bir `data-loading` attribute delegation'a bakılabilir ama şimdilik ihtiyaç yok.

---

## Karar 3 — 2026-07-30
### Kararı
Scheduler API sözleşmesi genişletildi: `GET /api/scheduler/queue` yanıtına `config_enabled`, `auto_upload`, `daily_limit`, `default_times` alanları eklendi. UI, bu alanları scheduler kapalı olduğunda kullanıcıya YAML örneği + copy-paste kolaylığı sunmak için kullanıyor.

### Neden
- `config.yaml`'da `scheduler:` bloğu yoksa background thread hiç başlamıyor (bkz. `app.py:_start_scheduler`) fakat UI bunu bilmiyordu; kullanıcı "Yayın Kuyruğu" sayfasını görüyor ama neden çalışmadığını anlamıyordu.
- Yeni endpoint eklemek yerine mevcut summary endpoint'i zenginleştirmek daha az yüzey; frontend zaten bu endpoint'i çağırıyor.

### Değerlendirilen alternatifler
1. **`GET /api/scheduler/status`** — yeni endpoint. Reddedildi: iki round-trip fazladan.
2. **`config_enabled` alanını `GET /api/status`'a eklemek** — genel status endpoint'i şişer. Reddedildi.
3. **Mevcut endpoint'e ek alanlar** — geriye uyumlu, tek round-trip. **Kabul**.

### Ödünler
- **Yararı**: UI bir bakışta config eksikliğini fark eder ve kullanıcıya somut YAML gösterir.
- **Maliyet**: response schema büyür (~120 byte); mobilde önemsiz.

### Sonuçları
- Her scheduler UI değişikliği artık bu 4 alanı kullanabilir.
- Aynı model diğer opsiyonel bölümler için de tekrar edilebilir (`GET /api/tiktok/status` zaten `enabled` döndürüyor, tutarlı).

---

## Karar 2 — 2026-07-30
### Kararı
Reels kartlarına "🗓 Kuyruğa" butonu eklendi. `POST /api/scheduler/queue` endpoint'i UI'dan tetiklenir hâle geldi.

### Neden
- Scheduler kodu (`src/scheduler.py`, 367 satır) tam işlevli; enqueue API var, ama UI'da hiç çağıran yoktu. Endpoint orphan idi.
- Kullanıcı "üret → kuyruğa al → sonraki slot'ta yayınla" akışını tamamlayamıyordu.

### Değerlendirilen alternatifler
1. **Otomatik enqueue** — reel üretildiği anda kuyruğa gir. Reddedildi: kullanıcı hangi reel'i yayınlayacağına karar vermek istiyor (bazıları test).
2. **Batch modal** — birden fazla reel'i tek modaldan enqueue. Reddedildi: MVP için tek buton yeterli; batch ihtiyacı görülünce eklenir.
3. **Buton her karta** — **kabul**. `🗓 Kuyruğa` primary değil, secondary-row'da (Drive'a Gönder primary kalıyor).

### Ödünler
- **Yararı**: uçtan uca akış tamamlandı, hiçbir endpoint orphan değil.
- **Maliyet**: kart yüksekliği ~30px arttı — mobil dizilimde henüz sorun yok.

### Sonuçları
- Analytics `platform_compare` metriğinde yakında schedule-vs-manual eğilimi ölçülebilir.
- İleride "Toplu kuyruk oluştur" seçeneği eklenebilir (secondary-row `+ Kuyruğa Ekle` menüsü).

---

## Karar 1 — 2026-07-30
### Kararı
Scheduler'ı manuel yayın moduyla (`auto_upload: false`) başlatmak default önerisi. Kullanıcı config'e `enabled: true` ekleyerek scheduler'ı aktif etmedikçe kod dokunulmaz kalacak.

### Neden
- Instagram Graph API rate limit ve kalite kontrolü açısından `auto_upload: true` önerilmez (kanal @japonyaruyasi belgesel, editöryel gate önemli).
- `auto_upload: false` ise scheduler kartı `status='ready'` yapar, kullanıcı UI'dan görüp yayınlar → aynı editörial disiplin korunur.
- `enabled: true` + `auto_upload: false`: scheduler "hatırlatıcı" gibi çalışır — slot atar, ready'ye alır, yayın kararını kullanıcıya bırakır.

### Değerlendirilen alternatifler
1. **`auto_upload: true` default** — hızlı ama yayın kalitesi bekçisiz. Reddedildi.
2. **Scheduler'ı kaldır** — kodu yalın tut. Reddedildi: haftada 2 post kadansı için lazım.
3. **`enabled: true, auto_upload: false` default** — **kabul**. Middle ground.

### Ödünler
- **Yararı**: kanal kalitesi korunur, otomasyon avantajı (slot planlama) devrede.
- **Maliyet**: kullanıcı yine yayın butonuna basmak zorunda — tam otomasyon değil.

### Sonuçları
- `config.yaml.example`'a scheduler bloğu eklenecek (henüz eklenmedi; sıradaki iş).
- İleri aşamada "onaylı auto" (editorial gate + human approval → auto publish) mekanizması düşünülebilir.

---

## Şablon (yeni karar için kopyala)

```
## Karar N — YYYY-MM-DD
### Kararı
<Ne karar verildi? Tek cümle.>

### Neden
<Motivasyon: kullanıcı ihtiyacı, bug, teknik kısıt, iş hedefi.>

### Değerlendirilen alternatifler
1. **Seçenek A** — reddedildi çünkü ...
2. **Seçenek B** — reddedildi çünkü ...
3. **Seçenek C** — kabul edildi çünkü ... (**Kabul**)

### Ödünler
- **Yararı**: ...
- **Maliyet**: ...

### Sonuçları
- <Sistemsel değişiklik>
- <Sonraki adımlar / kısıtlar>
```
