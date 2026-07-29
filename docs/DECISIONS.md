# DECISIONS.md — Mühendislik Kararları

> Sadece **append**. Eski kayıt silinmez; yanlış çıkarsa altına yeni bir
> kayıt eklenir ve orijinali *supersedes* alanıyla bağlanır.

---

## 2026-07-22 — Marka: **Rotori** (Tabi'den rebrand)

**Karar:** Marka adı **Rotori** olarak sabitlendi. Uygulama title'ı
(`main.dart` → `title: 'Rotori'`), tanıtım sitesi (`website/index.html`) ve
metinler tutarlı hale getirildi.

**Neden:** "Tabi" (旅) Japonca köke bağlıydı ama global App Store aramasında
zayıf ayırt ediciydi; ayrıca Türkçe konuşurken "tabii" ile karışabiliyordu.
Rotori hem daha ayırt edici hem de "rota + tori (kuş)" çağrışımıyla ürünle
uyumlu.

**Alternatifler değerlendirilen:**
- Tabi (旅) — özgün ilk öneri
- Sakura Route
- Nihon Rota

**Trade-off'lar:** Tabi'nin Japonya-özgün semantik bağı kayboldu; Rotori
markasının kültürel bağı daha soft. Kabul edildi çünkü hedef pazar (Türk
gezginler) için "Japonya" zaten üründe zımnen var.

**Sonuç:** `[[launch-website-tabi]]` memory'sindeki "Tabi" adı artık
tarihsel. Site + uygulama Rotori. Commit izi: `360e5ae`.

---

## 2026-07-07 — React web'i **Flutter mobile'a 1:1 port** et

**Karar:** `apps/planner` + `apps/viewer` React uygulamaları Flutter tarafına
(`mobile/`) birebir taşındı. Mobil (iPhone-first) birincil ürün oldu.

**Neden:** App Store'da yer almak, offline harita/geofence gibi native yetenekler,
tek codebase'de iOS + web preview (via device_preview).

**Alternatifler:** React Native, Capacitor sarma, PWA-only devam.

**Trade-off'lar:**
- **Kazanç:** Native performans, offline-first, ML Kit OCR, App Store dağıtımı.
- **Kayıp:** Web tarafı bakım moduna geçti; iki paralel kod tabanı (kısa vadede).

**Sonuç:** `mobile/lib/domain/` `packages/shared/src/types.ts`'i aynalar;
domain saf Dart, `flutter analyze` 0 error hedefli.

---

## 2026-07-07 — Domain katmanı **saf Dart** (Flutter import etmez)

**Karar:** `mobile/lib/domain/*.dart` içindeki hiçbir dosya `flutter/*` veya
`supabase_flutter` import etmez.

**Neden:** Hızlı unit test, platformdan bağımsız iş kuralı, ileride başka
UI hedeflerine (macOS / desktop) taşınabilirlik.

**Alternatifler:** Widget'la iç içe domain — kısa vadede hızlı ama test edilemez.

**Sonuç:** `flutter test` altındaki 236+ test hızlı çalışıyor. Her yeni
domain dosyası testli girer (bkz. `day_schedule.dart` + testi).

---

## 2026-07-x — **Riverpod** + **go_router** kombinasyonu

**Karar:** State için `flutter_riverpod`, routing için `go_router`.

**Neden:** Riverpod compile-time güvenli, `AsyncNotifier` Supabase ile temiz
uyum; go_router deep-link + guard için modern.

**Alternatifler:** Bloc (fazla ceremony), Provider (state modelleri düşük),
auto_route (learning curve daha büyük).

**Sonuç:** `authProvider` → router guard zinciri kuruldu. Provider adları
`xxxProvider` konvansiyonu.

---

## 2026-07-x — **Supabase** (self-hosted değil, hosted)

**Karar:** Backend olarak Supabase (proje ref `vsclzcillbveregzsgmj`,
Tokyo bölgesi ap-northeast-1). Auth + `plans` + `profiles` + RLS.

**Neden:** Auth (email + Google + Apple), RLS ile satır seviyesi güvenlik,
Postgres, migration disiplini, storage bonus. Hosted olduğu için sunucu
bakımı yok — F1'de asıl mesele App Store'a çıkmak.

**Alternatifler:** Firebase (Google bağımlılığı + yeniden yazım), kendi Node/Postgres
(bakım yükü), Appwrite (olgunluk).

**Trade-off:** Tek satıcıya bağımlılık. Kabul, çünkü şema Postgres — ihraç
yolu açık.

**Prod öncesi zorunlu:** Supabase Auth "Confirm email" **açılacak** (şu an
test için kapalı — `mailer_autoconfirm:true`). Bu bir *unresolved decision*
olarak kalmalıdır.

---

## 2026-07-x — Tanıtım sitesi **tek dosya, self-contained**

**Karar:** `website/index.html` inline CSS/JS/SVG. Harici asset yok.

**Neden:** Basit deploy (rsync), CDN karmaşası yok, prompt-injection yüzeyi
minimal, çevrimdışı görüntülenebilir.

**Alternatifler:** Astro/Next tabanlı bir mikro-site.

**Trade-off:** Dosya büyür (~200 KB civarında). Kabul — hâlâ tek istek.

**Sonuç:** Design System v2 (`4578280`) aynı disiplinle geldi. `window.__i18nAudit()`
i18n bütünlüğünü doğruluyor.

---

## 2026-07-x — **i18n el yapımı** (`intl` codegen yerine)

**Karar:** `lib/core/l10n.dart` içinde manuel sözlük + `LText` inline.

**Neden:** Runtime dil switch'i (kullanıcı tercihini kalıcılaştır),
codegen aşamasız iterasyon, büyük içerik (city_places, place_guide) için
inline `LText(tr, en)` daha esnek.

**Alternatifler:** `intl` + arb + codegen — enterprise düzeyi ama iterasyon
maliyetli.

**Trade-off:** Anahtar kaçırma riski var — buna karşı `.__i18nAudit()`
(site) ve `flutter analyze`'in tetikleyeceği eksik anahtar hataları
kullanılıyor.

**Kabul edilen sınır:** Üretilen plan içeriği (itinerary_generator +
fillEmptyDays) *üretim anındaki dilde donar*; sonradan dil değişirse plan
yeniden çevrilmez.

---

## 2026-07-x — Web hedefi **conditional import ile graceful**

**Karar:** Mobil-only paketler (ML Kit OCR, `flutter_local_notifications`,
`flutter_cache_manager` file cache, `home_widget`) web build'ine sızmaz.
Her biri `kIsWeb` kapısı veya conditional import ile no-op'a düşer.

**Neden:** `preview_main.dart` ile web-preview üzerinden tasarım/QA yapılıyor;
build kırılmamalı.

**Alternatifler:** Web derlemesini bütünüyle kapatmak.

**Sonuç:** `data/ticket_ocr.dart` conditional import (`ticket_ocr_stub.dart` /
`ticket_ocr_mlkit.dart`). Home widget web'de sessizce düşer (`home_widget_hook.dart`).

---

## 2026-07-x — Harita: **OSM raster tile** + kendi cache

**Karar:** Harita için `flutter_map` + OSM raster tile. API key yok. Cache
`flutter_cache_manager` ile.

**Neden:** Ücretsiz, key yönetimi yok, çevrimdışı-öncelikli, App Store'da
key sızıntısı riski yok.

**Alternatifler:** Mapbox (key + fatura), Google Maps SDK (fatura + Apple
uyum çıtası).

**Trade-off:** Görsel kalite OSM'de. Kabul — plan yönlendirme + geofence için
yeterli.

---

## 2026-07-x — GPS keşif: dwell 600 s, grace 120 s, radius+min(accuracy,80)

**Karar:** Geofence tetiklemesi için dwell süresi 600 saniye, grace 120 saniye,
eşik `radius + min(accuracy, 80)` metre.

**Neden:** iPhone GPS aksürasi değişken; kısa dwell false-positive üretiyor,
uzun dwell UX'i öldürüyor. 600/120 kombinasyonu kullanıcı test'inde stabildi.

**Alternatifler:** iOS `CLRegion` (native geofence) — arka planda daha güçlü
ama Flutter köprü karmaşası.

**Sonuç:** `lib/features/viewer/geofence_service.dart` içinde. React tarafında
`apps/viewer/src/hooks/useGeofence.ts` matematiksel aynası — port doğrulandı.

---

## 2026-07-x — QA: **kod-içi senaryo dashboard'u**

**Karar:** Playwright/E2E harici bir framework yerine uygulama içinde bir QA
dashboard + `gps_sim_screen.dart` simülasyon aracı.

**Neden:** Flutter tek codebase; test framework fragmantasyonu istemedik;
gerçek widget davranışını doğrulamak native flutter test paketiyle daha hızlı.

**Alternatifler:** `integration_test` paketi + Playwright web.

**Sonuç:** 110 senaryo · 95 otomatik %100 pass (`888feb2`).

---

## 2026-07-29 — /docs mimarisi kalıcılaştırıldı

**Karar:** `docs/CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CURRENT_TASK.md`,
`docs/DECISIONS.md` proje bilgi zeminini oluşturur. Her feature bitişinde
güncellenir; kod ve döküman uyumsuz kalırsa **önce döküman düzeltilir**.

**Neden:** Oturumlar arası bilgi kaybını engellemek. Memory sistemi (~/.claude)
oturum yardımcısıdır; repo içi `/docs` tek gerçek kaynağıdır.

**Alternatifler:** README genişletme, wiki, notion.

**Sonuç:** Bu dosya bugün eklendi. `PHASE2-ROUTING.md` (Haziran '26) tarihsel
referans olarak `docs/` altında kalır.
