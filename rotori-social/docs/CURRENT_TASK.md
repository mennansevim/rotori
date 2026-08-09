# CURRENT_TASK.md — Aktif İş

> Görev tamamlanır tamamlanmaz güncellenir. Sadece **bugünkü** işi tutar; geçmiş `DECISIONS.md`'e taşınır.
> Son güncelleme: 2026-08-10 (mavi haber akışı haftalık sıra düzeltmesi)

## 2026-08-10 — Tamamlanan iş

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
- Dashboard modül cache anahtarı `20260810-4` sürümüne yükseltildi; ana HTML
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
