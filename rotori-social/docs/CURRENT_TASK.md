# CURRENT_TASK.md — Aktif İş

> Görev tamamlanır tamamlanmaz güncellenir. Sadece **bugünkü** işi tutar; geçmiş `DECISIONS.md`'e taşınır.
> Son güncelleme: 2026-08-10 (otomasyon algoritması: bulk dayanıklılığı + konu tekrarı)

## 2026-08-11 — Görsel arama sorgusu zenginleştirildi

### Belirti ve teşhis
- Kullanıcı: "teamlabs yazınca saçmalıyor, teamlab planets yazmama rağmen
  çıkmadı." Gerçek Unsplash ölçümü teşhisi doğruladı:
  `teamlabs` → **3 sonuç** (saat kulesi, rastgele portre);
  `immersive digital art installation japan` → **2068 sonuç** (ışık enstalasyonu).
- Kök neden: manuel görsel aramada **hiç sorgu zenginleştirme yoktu** — kullanıcının
  yazdığı kelime `POST /api/backgrounds/preview` → `search_only` üzerinden ham
  hâlde Unsplash'e gidiyordu.
- **Bu bir regresyon değil**: eski `studio.html` da aynı endpoint'e ham sorgu
  gönderiyordu (kod okundu) ve `downloader.py` geçmişinde hiç zenginleştirme
  eklenip kaldırılmamış (git log). "Eskiden iyi arıyordu" hissi otomasyon
  yolundan geliyor: orada LLM `gorsel_konsepti` üretiyor (marka adı yasak,
  genel sahne) ve `_pick_image` "japan …" kademesini uyguluyordu.

### Yapılan
- `downloader.enrich_query` / `build_search_queries` / `search_with_fallback`:
  marka → sahne eşlemesi (teamLab, USJ, Disneyland, DisneySea, Ghibli, Pokémon,
  konbini zincirleri, JR Pass, Suica…), Türkçe → İngilizce gövde eşlemeli sözlük,
  Japonya çıpası, kademeli + **biriktiren** fallback (grid 10'a tamamlanır),
  kota için en fazla 3 istek.
- `POST /api/backgrounds/preview` → yanıta `effective_query` + `tried` eklendi.
- Dashboard: `picker-query-note` şeridi "teamlabs → japan immersive digital art
  installation dark room · stok fotoğrafta bulunabilir sahneye çevrildi" gösteriyor.
- `news_automation._pick_image` kendi ad-hoc kademesini bıraktı, ortak yardımcıyı
  kullanıyor.

### Stil 1 / Stil 2 sorusu — kaldırılmamış
- Seçici duruyor: **Yeni İçerik → Görsel Üret → 3. Metin** adımında, "Üst rozet"in
  yanında "KART STİLİ" başlığıyla (`create.js` `stylePicker`, CSS `.style-picker`).
  Tarayıcıda doğrulandı; varsayılan Stil 2 (Japonya Rüyası wordmark).
- Fark şu: eski `studio.html`'de seçici üretim formunun başındaydı, modüler
  dashboard'da 3. adıma (görsel seçildikten sonra) taşınmış. Gözden kaçması bu
  yüzden. İstenirse 1. adıma alınabilir — bu bir yerleşim kararı.

### Doğrulama
- `pytest -q tests/` → **171 passed** (yeni:
  `tests/test_image_search_enrichment.py`, 36 test).
- Gerçek tarayıcıda: `teamlabs` araması → 10 ilgili görsel + çeviri şeridi;
  seçilen kart önizlemesinde karanlık ışık enstalasyonu fotoğrafı.
- Dashboard cache anahtarı `20260810-8`.
- Doğrulamada OpenAI çağrısı tetiklenmedi (metin alanı önceden doldurularak
  otomatik AI çağrısı engellendi); Unsplash'e toplam ~6 arama isteği gitti.

## 2026-08-10 — Otomasyon algoritması: üç arıza giderildi

### 1. Toplu üretim kısmi hatada çöküyordu
- Belirti: "10 haber üret" hata veriyor ama arkada 6-7 kart oluşmuş.
- Kök neden: `_run_now_bulk` turları exception yakalamadan çalıştırıyordu;
  `run_once` görsel bulamayınca `RuntimeError` atıyor (Unsplash free tier
  saatlik 50 istek limiti 10 turda dolabiliyor) → iş "hata" olarak kapanıyor.
- Çözüm: her tur ayrı sarıldı; hata "atlandı" satırı olur ve üretim devam eder.
  Üst üste 3 hata → devre kesici. Kısmi başarı artık hata değil:
  `📦 Bulk tamamlandı: 9/10 kart üretildi · 1 hata`.
- Görsel bulunamaması exception değil, `reason="no_image"` sonucu oldu.

### 2. Aynı konular tekrar tekrar üretiliyordu
- Kök neden: havuz tükendiğinde `fresh_topics = list(pool)` ile TÜM havuz
  sessizce geri açılıyordu. Kanıt: 25 konuluk havuzda taze konu **0**; Pi
  history'sinde 56 kayıttan 16'sı tekrar (Kar Mevsimi 4x, Sakura 4x,
  Sonbahar Yaprakları 4x, Fushimi Inari 3x). Aynı satır
  `topic_automation._pick_topic` içinde de vardı.
- Çözüm: **cooldown** — bir konu `topic_cooldown_days` (45) geçmeden dönmez;
  süresi dolanlar **en eski kullanılan önce** yarışır. Havuz tükenip cooldown da
  dolmadıysa evergreen fazı açık uyarıyla atlanır (sessiz tekrar yok).
- Dedup güçlendirildi: kayıt başına 4 anahtar (link, başlık-link, normalize
  başlık, eski şema) → aynı konu **farklı kaynaktan** gelse de yakalanır.
  Normalizasyon Türkçe i/I/İ/ı varyantlarını tek harfe indiriyor.
- `used_ids` artık sıra koruyarak saklanıyor (`list(set)[-CAP:]` hatası giderildi),
  `_USED_CAP` 200 → 800.

### 3. İpucu niteliğinde konular havuzda yoktu
- `assets/topic_pool.json` 25 → **57 konu**: ulaşım (JR Pass, Suica/IC kart,
  gece otobüsü, havalimanı transferi, metro aktarma, bavul dolabı/kargo, feribot),
  konaklama (kapsül otel, business hotel, minshuku, shukubo, onsen kuralları),
  tema parkı (Universal Studios Japan, Tokyo Disneyland, DisneySea, teamLab,
  Skytree, sıra taktiği) ve pratik kurallar (eSIM, tax-free, konbini ATM, çöp,
  tapınak adabı, otomat menü, ödeme adabı, yürüyen merdiven, tren sessizliği,
  ayakkabı).
- Unsplash sorguları marka adı içermiyor (mevcut "stok fotoğrafta bulunmalı"
  kuralı) — testle kilitli.
- RSS seçim prompt'una da ulaşım/konaklama/tema parkı/ziyaretçi kuralı
  öncelikleri eklendi.
- Bonus: `topic` ve `downloader` logger'ları canlı süreç paneline bağlandı;
  konu otomasyonu ve Unsplash limit hataları artık UI'da görünüyor.

### Doğrulama
- `pytest -q tests/` → **135 passed** (yeni:
  `tests/test_automation_dedup_and_bulk.py`, 15 test).
- Pi'nin gerçek state'i üzerinde simülasyon: eski havuzla 0 taze konu
  (eski kod 25'ini geri açıyordu) → yeni havuzla **32 uygun konu**, hepsi
  yeni pratik ipucu başlıkları.
- Hiçbir gerçek OpenAI/Unsplash/Instagram çağrısı yapılmadı; testler stub kullanır.

## 2026-08-10 — Otomasyon ekranı tek görünüme indirildi (önceki iş)

- `Yayın Akışı` / `Yayın Düzeni` sekmeleri kaldırıldı; ekran tek görünüm.
- Her akışın yayın düzeni (gün seçici + saat + "saati gelince otomatik yayınla")
  ilgili akış kartının **içinde, slotların üstünde** duruyor.
- Akış kartı başlığına **Açık / Kapalı** anahtarı eklendi. Kapalı akış listeden
  düşmüyor; düzeni görünür kalıyor ve "Bu akış kapalı" bilgisi veriyor.
- Kaydetme lane bazlı: düzen değiştiğinde kartın içinde
  `Kaydedilmemiş düzen · Vazgeç · Kaydet` şeridi açılıyor; global
  "Ayarları Kaydet" düğmesi kaldırıldı.
- Akışı kapatmak planlı içerikleri iptal ettiği için onay modalı etkilenen
  içerik sayısını söylüyor ("14 planlı haber içeriği yayın sırasından
  çıkarılacak…"). Haber akışı gün seçilmemişken açılmaya çalışılırsa istemci
  422 beklemeden uyarıyor.
- 30 saniyelik otomatik yenileme, kaydedilmemiş düzen veya odaklı bir alan
  varken atlanıyor — kullanıcının girdiği değer ezilmiyor.
- **Yayın Geçmişi** kartı akış kartlarının altına alındı: ilk 5 kayıt +
  "Tüm geçmişi göster", Kütüphane arşivine kısayol.
- Ayarlar ekranındaki "Yayın düzenini aç" kısayolu artık akış kartlarındaki
  düzen şeritlerini vurguluyor (`automation:settings` → scroll + highlight).
- Dashboard cache anahtarı `20260810-7` sürümüne yükseltildi.

### Doğrulama
- `pytest -q tests/` → **120 passed** (yeni:
  `test_automation_lane_config_lives_inside_flow_card`).
- `node --input-type=module` ile `automation.js` sözdizimi kontrolü temiz.
- Gerçek tarayıcı (1440×1000 ve 375×812): akış kartı içi düzen, kirli/temiz
  şerit, `Vazgeç` ile geri alma, kapatma onay modalı ve iptali, kapalı akış boş
  durumu, yayın geçmişi doğrulandı. Konsol hatası yok, yatay taşma yok.
- Doğrulama sırasında hiçbir kayıt yapılmadı: `data/automation_config.json` ve
  `data/scheduler_queue.json` dokunulmadı (mtime 12:52, oturum öncesi).

## 2026-08-10 — Önceki iş (Genel Bakış / UX denetimi)

- Modüler dashboard demo kullanıcı olarak uçtan uca denetlendi; varsayılan
  açılış teknik Otomasyon ekranından karar odaklı **Genel Bakış** ekranına
  taşındı.
- Menü ve çalışma alanındaki İngilizce/Türkçe karışımı giderildi:
  **Genel Bakış / Kütüphane / Otomasyon / Aktivite / Ayarlar**.
- Genel Bakış; üç aşamalı yaşam döngüsü, sıradaki yayın, dikkat gereken işler
  ve haftalık yayın planını tek ekranda birleştiriyor.
- Otomasyonda tek kart seçimi toplu planlama yerine seçilen içeriği planlıyor;
  “Şimdi yayınla” ve Aktivite ekranındaki “Tekrar dene” eylemleri açık onay
  gerektiriyor.
- Ayarlar ekranındaki kaydedilmeyen sahte seçimler kaldırıldı; hesap sağlığı,
  yayın düzeni, saat dilimi ve güvenli gelişmiş hesap işlemleri ayrıldı.
- Ham sistem hataları Aktivite ekranında kullanıcı diline çevrildi; teknik
  ayrıntılar isteğe bağlı açılır bölümde korundu.
- Masaüstü ve 390×844 mobil görünüm gerçek tarayıcıda doğrulandı; dashboard
  cache anahtarı `20260810-6` sürümüne yükseltildi.
- Kütüphane baştan tasarlandı ve ana içerik yaşam döngüsü üç aşamaya
  sabitlendi: **Taslak → Onaylandı → Yayınlandı**.
- Otomasyon ayrı bir içerik durumu olmaktan çıkarıldı; planlanan kartlar
  Onaylandı aşamasında `Otomasyonda` alt durumu ve yayın tarihiyle görünür.
- Taslaklar kart üzerinden onaylanabilir; onaylanan içerikler tek tek veya
  açıkça adlandırılmış toplu eylemle otomasyona eklenebilir. Tekli eylem artık
  yanlışlıkla tüm onaylı havuzu planlamaz.
- Yayın kaydı oluştuğunda içerik API'nin `published` durumuyla otomatik olarak
  Yayınlandı arşivine taşınır.
- Masaüstü ve mobil için yeni aşama navigasyonu, filtreler, içerik kartları,
  zamanlama/yayın panelleri ve boş durumlar eklendi.
- Mavi haber otomasyonu Çarşamba 23:21'de haftada bir çalışacak şekilde
  tek güne indirildi; bekleyen 10 haber kartı yedişer gün arayla yeniden
  sıralandı.
- Haber gün seçicisi çoklu seçimden tek seçime çevrildi ve API aynı kuralı
  `422` doğrulamasıyla koruyor.
- Geçmiş `failed/cancelled` kayıtlar canlı flow sırasından çıkarıldı; loglarda
  görünmeye devam ediyor.
- Flow başlığı gerçek kadansı (`Haftada 1 · Çar 23:21`) ve bekleyen içerik
  sayısını gösteriyor; ilk beş aktif haftalık kart tarih sırasıyla görünür.
- İlgili scheduler, API ve dashboard regresyon testleri eklendi.
- Dashboard modül cache anahtarı `20260810-6` sürümüne yükseltildi; ana HTML
  no-store yanıtıyla birlikte eski otomasyon JavaScript'inin tutulması önlendi.
- Her deploy benzersiz UTC build kimliği üretir ve `/api/version` bunu SemVer
  build metadata olarak gösterir. Dashboard statik dosyaları ayrıca kalıcı
  `no-store` politikasıyla sunulur.

## Sprint hedefi (yeni)
**"japonya-ruyasi-dashboard-design.zip paketindeki editöryel dashboard tasarımını üretim kalitesinde uygula; mevcut endpoint'leri koru; eski arayüzü kaldırma."**

- Yeni tek dosyalı SPA: `src/web/static/studio.html`
- Feature flag: `GET /` route'u `?ui=new` veya `?ui=studio` query param'ı ile yeni arayüzü sunar; `/studio` da doğrudan yeni UI'yi verir.
- Eski `index.html` `/` kök adresinde varsayılan olarak kalır — kaldırılmadı.
- Görsel dil, tipografi, spacing, sidebar/topbar yerleşimi ve responsive kırılımlar tasarım prototipine sadıktır.

## Bağlanan API'ler (bileşen ↔ endpoint)
| Ekran | Bileşen | Endpoint(ler) |
|---|---|---|
| Genel Bakış | Karşılama başlığı & lead | `GET /api/approval/list`, `GET /api/scheduler/queue` |
| Genel Bakış | Fırsat kartı (Fuji sezonu) | `GET /api/analytics/hooks` (winner) |
| Genel Bakış | Haftalık hedef skoru | `GET /api/analytics/overview?days=30` (avg_per_week_ig, recommended_weekly) |
| Genel Bakış | Sıradaki yayın | `GET /api/scheduler/queue` (next_scheduled) |
| Genel Bakış | 4 KPI kartı + sparkline | `GET /api/analytics/overview` (total_ig, daily_ig, avg_per_week_ig, pending) |
| Genel Bakış | Yaklaşan içerikler | `GET /api/scheduler/queue` (items[])
| Genel Bakış | Son hareketler | overview + approval + öneri metinlerinden derivatif |
| AI Stüdyo | Tek görsel / Carousel / Story üret | `POST /api/story/generate` |
| AI Stüdyo | Reel üret | `POST /api/generate/prompt` |
| AI Stüdyo | Telefon önizleme | client-side; üretim sonrası ilk kart URL'i inject edilir |
| Takvim | Aylık grid | `GET /api/scheduler/queue` (items[].scheduled_at, status) |
| Kütüphane | Kartlar + Reels | `GET /api/story/list`, `GET /api/reels` (pending/ready/published gruplarını flatten) |
| Kütüphane | Detay modalı | `POST /api/story/mark_ready/{name}`, `POST /api/instagram/publish/{name}`, `DELETE /api/story/{name}`, `POST /api/scheduler/queue`, `POST /api/tiktok/upload` |
| Yayın Kuyruğu | Taslak sütunu | `GET /api/story/list` (ready=false, published=false) |
| Yayın Kuyruğu | Onay bekliyor | `GET /api/approval/list`, `POST /api/approval/approve|reject/{name}` |
| Yayın Kuyruğu | Planlandı | `GET /api/scheduler/queue`, `DELETE /api/scheduler/queue/{id}` |
| Analiz | 4 KPI + trend chart | `GET /api/analytics/overview?days=N` (daily_ig/daily_tiktok haftalık bucket'lara alınır) |
| Analiz | AI içgörüleri | `GET /api/analytics/hooks`, `GET /api/analytics/platforms` |
| Ayarlar | Instagram bağlantı | `GET /api/instagram/graph_status` |
| Ayarlar | TikTok bağlantı | `GET /api/tiktok/status`, `POST /api/tiktok/refresh_token` |
| Ayarlar | Scheduler ayarı | `GET /api/scheduler/queue` (config_enabled, auto_upload, daily_limit, default_times), `POST /api/scheduler/run` |
| Ayarlar | Otomasyon | `GET /api/automation/config`, `POST /api/news/run_now`, `POST /api/automation/run_now?kind=topic` |

## Değişen dosyalar
- **Yeni**: `src/web/static/studio.html` — tek dosyalı SPA (~1100 satır HTML/CSS/JS).
- **Yeni**: `src/web/static/japan-editorial-grid.png` — tasarım paketindeki 6 sahneli Japan editorial atlası (background-position ile parçalanır).
- **Değişti**: `src/web/app.py` — `Request` import + `/` feature-flag + yeni `/studio` route.

## Görsel/UX doğrulama (tarayıcıda test edildi)
- [x] Genel Bakış: gerçek "2 IG yayını / 0.5 hafta / hedef 7" değerleri; date "30 Temmuz Perşembe"; hero "Bugünün üretim önerisi" (hook verisi henüz yok).
- [x] AI Stüdyo: chips (Tek görsel/Carousel/Reel/Story) aktif, telefon önizleme başlık+alt yazı canlı.
- [x] Takvim: Temmuz 2026, önceki/sonraki ay çalışıyor, boş kuyrukta doğru boş durum.
- [x] Kütüphane: 32 öğe (26 görsel + 6 reels), filtre chip'leri sayaçlı; detay modal reel için video + kuyruk butonları, kart için mark_ready + publish + delete.
- [x] Yayın Kuyruğu: 3 sütun kanban (Taslak 19 / Onay bekliyor 0 / Planlandı 0), "Otomasyon: Açık ●" scheduler config'i yansıtıyor.
- [x] Analiz: haftalık bar chart (son 8 hafta bucket'ı), IG/TikTok metrik toggle, AI içgörüleri (frekans + platform + hook winner).
- [x] Ayarlar: Instagram Business bağlı, TikTok "Bağla" durumu, sol menü sekmeleri çalışıyor.
- [x] Mobil (533×784): sidebar altına ikon tab bar iner, tek sütun düzen, dokunma hedefleri >40px.
- [x] Konsol hatası yok.

## Korunan sözleşmeler
- 66 API route aynen; sadece iki yeni serve endpoint eklendi (`/studio`, `/?ui=new`).
- Eski `index.html` bozulmadı — `/` default olarak eski arayüzü sunar.
- `config.yaml`, scheduler, editorial gate, otomasyon aynı.
- pytest -q başarılı (kontrat testleri değişmedi).

## Bekleyen (opsiyonel iyileştirmeler)
- Yayın kuyruğu taslak sütunundaki story kartları için `.thumb img` height'ı 135px'te bazı sekmelerinde küçük render; sonraki iterasyonda `object-fit:cover` + explicit ratio.
- Toggle bileşenleri config'i canlı güncelleyecek endpoint istiyor (şimdi bilgi mesajıyla YAML düzenlemeye yönlendiriyor).
- Search input yer tutucu; endpoint bağlı değil.
- Takvim sürükle-bırak yeniden planlama (design spec önerisi) sonraki iterasyon.

## Mevcut branch
`main` — commit'lenmedi. Bir önceki UX refactor commit'i (Karar 9) da hâlâ staged değil.

Kullanıcı uygulamayı açtığında teknik modülleri öğrenmeden şu sırayı izleyebilmeli:

`Bugün → Hazırlık → Yayına Hazır → Otomasyon`

## Piyasa incelemesinden alınan ilkeler
- **Later**: içerik kütüphanesi, taslak ve takvim ayrı zihinsel alanlar.
- **Buffer**: sıradaki yayın ve kuyruk görünümü birincil.
- **Metricool / Hootsuite**: onay durumu ve sonraki karar görünür; ayarlar ana akışın önüne geçmez.
- Bu projeye uyarlanan sonuç: ana menü teknik özellikleri değil içerik durumlarını göstermeli.

## Bu iterasyonda tamamlanan
### Bilgi mimarisi
- [x] Sidebar yedi teknik hedeften beş kullanıcı hedefine indirildi: Bugün, Hazırlık, Yayına Hazır, Otomasyon, İstatistikler.
- [x] Mobil için dört eşit hedefli yapışkan navigasyon eklendi.
- [x] `openWorkspace(view)` eklendi; eski `sideNav` geriye uyumluluk için korunuyor.

### Bugün
- [x] Beş hızlı eylem üç karar noktasına indirildi: İçerik hazırla, Onay bekleyenler, Yayın planı.
- [x] Birincil durum kartları İş / Onay / Sıradaki Yayın olarak sadeleştirildi.
- [x] Son üretilenler görünümü korundu.

### Hazırlık
- [x] Dört açık üretim seçeneği: Görsel kart, Haberden kart, Konudan kart, Reel metni.
- [x] Haber üretme fonksiyonu (`runNewsNow`) ve tüm API çağrıları değiştirilmedi.
- [x] Üretilen haber/görsel kart akordiyonları otomasyon ayarlarından ayrılarak taslak alanına taşındı.

### Yayına Hazır
- [x] Onay kuyruğu bağımsız görünüm hâline getirildi.
- [x] Onay sayısı sidebar rozetine bağlandı.
- [x] Kuyruk boşken açıklayıcı boş durum eklendi.

### Otomasyon
- [x] Haftalık haber ve konu akışlarının davranışı korunarak ayrı görünüme alındı.
- [x] Gün seçimleri ana görünümden kaldırıldı; ayrıntılı ayarlar mevcut modalda kaldı.
- [x] Karmaşık akış açıklama şeridi gizlendi; durum ve sıradaki gönderi öne çıkarıldı.

### Görsel dil
- [x] Gereksiz plan yükseltme kartı kaldırıldı; bağlı Instagram kanalı gösterildi.
- [x] Kart gölgeleri, yoğunluk ve metin boyları sadeleştirildi.
- [x] Masaüstü, tablet ve mobil için ayrı düzen kuralları eklendi.

## Korunan sözleşmeler
- 66 API route aynı URL, HTTP metodu ve yanıt yapısıyla duruyor.
- Haber, konu, görsel ve Reel üretim fonksiyonlarının içeriği değiştirilmedi.
- `config.yaml`, scheduler, editorial gate ve yayın mekanikleri değiştirilmedi.
- Eski global `switchTab` ve `sideNav` çağrıları çalışmaya devam ediyor.

## Doğrulama
- [x] `pytest -q tests/` → 8 passed, 3 mevcut deprecation warning
- [x] Inline JavaScript syntax kontrolü başarılı
- [x] `git diff --check` temiz
- [x] Yeni onclick hedefleri tanımlı
- [x] Dokümantasyon güncellendi (`CLAUDE`, `ARCHITECTURE`, `CURRENT_TASK`, `DECISIONS`)

## Mevcut branch
`main` — değişiklikler commit'lenmedi.

## Çalışma ağacındaki ayrı değişiklik
`data/automation_config.json` içindeki haber zamanı Perşembe 17:05 olarak değiştirilmiş durumda. Bu UI çalışması değişikliği sahiplenmedi veya geri almadı.

## Sonraki güvenli adımlar
1. Kullanıcı onayından sonra commit.
2. Gerekirse Pi5 deploy ve gerçek cihazda son görsel kontrol.
3. İleri iterasyonda `panel-cards` görünüm modlarını fiziksel bileşenlere ayırmak.
