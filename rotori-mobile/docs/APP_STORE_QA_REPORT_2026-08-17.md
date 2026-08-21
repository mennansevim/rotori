# App Store Çıkış Öncesi QA Raporu — Rotori Mobile

> Tarih: 2026-08-17 · Kapsam: `rotori-mobile/` (Flutter + Supabase) · Branch: `codex/apple-design-polish`
> Yöntem: statik kod incelemesi + `flutter analyze` + tam `flutter test` + QA senaryo koşucusu yeniden çalıştırma + iOS/Xcode yapılandırma denetimi.

---

## 1. Yönetici Özeti

Uygulama **App Store'a çıkmaya hazır değil.** Tek bir **release-blocker** var ve bu Apple incelemesinde kesin red sebebi:

> **Hesap silme akışı UI'a hiç bağlanmamış.** Backend/metot ve Türkçe/İngilizce metinler hazır, ama kullanıcıya ulaşan hiçbir ekran/buton yok. Apple Guideline 5.1.1(v), hesap oluşturma sunan her uygulamanın **uygulama içinden hesap silme** akışı sunmasını zorunlu kılar.

Bunun dışında çok sayıda P1 eksik (email onayı, gerçek cihaz testi, uygulama boyutu, premium/StoreKit) ve bir dizi performans + çevrimdışı dayanıklılık sorunu var. Kod kalitesi ve test altyapısı genel olarak **iyi** (analyze temiz, 540+ test yeşil, kapsamlı privacy manifest), ancak kritik yol tamamlanmamış.

| Boyut | Durum |
|---|---|
| `flutter analyze` | ✅ Temiz (0 sorun) |
| Tam birim/widget test paketi | ✅ Geçti (exit 0, 540+ test) |
| QA senaryo koşucusu | ⚠️ 88/95 geçti, **7 fail** (s04, s13, s14, s15, s20, s23, s85) |
| Apple hesap silme (5.1.1v) | ❌ UI bağlantısı yok (P0) |
| Widget Extension + App Group | ❌ Native target hiç oluşturulmamış (scope dışı bırakılabilir) |
| Email confirmation | ❌ Kapalı (prod'a açılmalı) |
| StoreKit / IAP | ❌ Yok — premium yerel debug bayrağı |
| Gerçek cihaz smoke test | ❌ Yapılamadı (Xcode/device-support uyumsuzluğu) |
| Uygulama boyutu | ⚠️ 132,7 MB (hedef ≤ 60 MB) |

---

## 2. P0 — Release Blocker

### P0-1 · Hesap silme akışı yok (Apple 5.1.1v) — **KESİN RED**
- `lib/features/auth/auth_repository.dart:71-87` → `deleteAccount()` Supabase RPC `delete_current_user` çağırıyor; doğru yazılmış (kendi verisini `security definer` + `auth.uid()` kontrolüyle siler).
- `lib/core/l10n.dart:3465-3488` → `drawer.deleteAccount`, `account.delete.title/body/confirm/cancel/error/success` metinleri hazır.
- **Ama `lib/` içinde `deleteAccount()`'a hiçbir çağrı yok.** Drawer'da yalnızca "Çıkış yap" tile'ı var (`lib/features/plans/widgets/plan_viewer_drawer.dart:248-261`).
- **Aksiyon:** Drawer'a "Hesabı sil" tile'ı + onay diyaloğu + silme sonrası auth ekranına yönlendirme ekle. Aynı anda `signOut`'tan farklı bir akış olduğundan emin ol.

### P0-2 · Email confirmation kapalı
- `docs/CLAUDE.md` §9 ve `TESTFLIGHT_READINESS.md` satır 53: Supabase Auth "Confirm email" şu an **test için kapalı**. Prod'a çıkmadan **açılmalı**; aksi halde kayıt akışı doğrulanmamış hesap kabul eder.
- **Aksiyon:** Supabase dashboard → Authentication → Providers → Email → "Confirm email" aç. Kayıt → onay → parola sıfırlama → tekrar giriş akışını gerçek cihazda doğrula.

### P0-3 · Gerçek cihaz smoke test yapılamadı
- `IOS_RELEASE_MANUAL_GATE_CHECKLIST.md:5-8` → 11 Ağustos denemesi: iPhone 14 / iOS 27 ile Xcode 26.6 developer disk image bağlanamadı, yükleme yapılamadı. Bu altyapı engeli çözülmeden hiçbir "PASS" iddia edilemez.
- **Aksiyon:** Xcode'u güncelle / cihaz iOS sürümüyle uyumlu Xcode sürümüyle yükle; cold launch + login/logout + Apple/Google login + plan kaydet/aç + uçak modu akışlarını gerçek cihazda kayda al.

### P0-4 · Uygulama boyutu hedefin ~2x üstü
- `TESTFLIGHT_READINESS.md:16` → imzasız `Runner.app` **132,7 MB**; `docs/CLAUDE.md` §8 hedefi **≤ 60 MB**.
- Asset'ler toplam **5,3 MB** (city-hero webp'ler 30–280 KB, TTS 2 MB) — şişkinlik asset'lerden değil; ML Kit çeviri + OCR + camera + Sentry + Flutter motoru + (muhtemel) tam sembol/gömülü kütüphane kaynaklı. App Store app-thinning indirilen boyutu düşürür ama hedefle fark araştırılmalı.
- **Aksiyon:** `flutter build ipa --release` sonrası `--split-debug-info` + `--obfuscate` ile final indirme boyutunu ölç; gerekirse ML Kit modellerinin "download on demand" olduğunu doğrula (modeller cihaza ilk kullanımda iniyor, bundle'a girmemeli).

### P0-5 · Apple imzalama / capability doğrulaması
- `ios/Runner.xcodeproj/project.pbxproj:532,720,744` → `DEVELOPMENT_TEAM = L3Z9U2B39K` var; `CODE_SIGN_ENTITLEMENTS` bağlı; `Runner.entitlements` içinde `com.apple.developer.applesignin = Default` var. ✅
- **RİSK:** Runner target build config'lerinde `CODE_SIGN_STYLE = Automatic` **yok** (yalnızca RunnerTests'te). Modern Flutter şablonu Runner'da da bunu açar; otomatik imzalamanın reproduce edilebilirliği için eklenmeli.
- **Aksiyon:** Xcode Signing & Capabilities'te Sign in with Apple capability'yi + App ID `com.mennansevim.rotori` + App Store provisioning profile'ı doğrula; geçerli Apple Distribution sertifikası oluştur.

---

## 3. P1 — Önemli

### 3.1 · StoreKit / IAP tamamen yok (monetizasyon)
- Premium **yalnızca yerel `debug_premium` SharedPreferences bayrağı** (`lib/features/plans/premium_provider.dart:17`). Abonelik modeli planlanmış (`docs/CLAUDE.md` §1: ₺499/yıl) ama satın alma akışı, restore, server-side JWS doğrulaması, entitlement ve App Store Server Notifications V2 **yok**.
- **Aksiyon:** İlk harici beta "yalnız bilgilendirme/paywall" ile çıkacaksa bunu Beta Review Notes'ta açıkça belirt. Aksi halde StoreKit akışını tamamla. `debug_premium` ve `raw_user_meta_data.premium` prod entitlement kaynağı olmaktan çıkarılmalı.

### 3.2 · Widget Extension + App Group (scope'a bağlı)
- `lib/features/viewer/home_widget_hook.dart:18` → `kRotoriAppGroupId = 'group.com.mennansevim.rotori'` yazılı; `HomeWidget.setAppGroupId` çağrılıyor. **Ama** `ios/` altında native Widget Extension target'ı (appex/NSExtension) ve App Group entitlement **hiç yok** (`Runner.entitlements` yalnızca apple sign-in içeriyor). Dart tarafı sessizce no-op'a düşüyor.
- **Aksiyon:** Widget ilk sürümde olacaksa `docs/IOS_WIDGET_SETUP.md` adımlarını uygula (target + App Group + SwiftUI). Olmayacaksa mağaza metninde widget vaadi verme — bu haliyle App Store için **engel değil**.

### 3.3 · Harita sağlayıcı SLA'sı
- Harita standart **OSM raster tile**, API key yok, disk cache yok (`lib/features/viewer/offline_tile_provider.dart:1-6`). Genel yayın ölçeğinde SLA/ticari kullanım sunan sağlayıcıya geçilmeli (`TESTFLIGHT_READINESS.md:124-130`).

### 3.4 · Yasal sayfalar
- TR/EN Kullanım Koşulları yayınlanmamış; Wikimedia/Unsplash görsel atıfları doğrulanmamış; "abonelik/IAP yok" metni gerçek Premium kapsamıyla eşleşmeli.

### 3.5 · iPad desteği
- `Info.plist` iPad orientation'ları var ama **hiçbir iPad gerçek cihaz testi yok**. İlk sürümde iPad desteklenecekse kritik ekranlar iPad'de doğrulanmalı; değilse device family kapsamı daraltılmalı.

---

## 4. Performans Bulguları

| # | Ciddiyet | Bulgu | Konum |
|---|---|---|---|
| P1 | 🔴 YÜKSEK | Plan optimizasyonu (BeamSearch) **ana UI thread'de**, `compute()`/`Isolate` hiç kullanılmıyor → optimize sırasında UI donar | `domain/itinerary_optimizer.dart:686-753`, `plan_optimization_controller.dart:167-169` |
| P2 | 🔴 YÜKSEK | Her optimizasyonda tam trip `toJson`/`fromJson` **en az 3x** ana thread'de (`_cloneTrip`) | `plan_optimization_controller.dart:812, 385, 392, 526` |
| P3 | 🟠 ORTA | Rota matrisi her seferinde sıfırdan kuruluyor; yazılmış `route_matrix_cache.dart` + `route_matrix_resolution.dart` **hiç enjekte edilmemiş** | `plan_optimization_controller.dart:144-146` |
| P4 | 🟠 ORTA | `buildOfflineJapanRouteMatrix` her rebuild'de O(n²) haversine + profil taraması, memoize yok | `plan_viewer_screen.dart:4638-4641` |
| P5 | 🟡 DÜŞÜK | Tile'lar yalnız oturum-içi RAM cache; disk cache yok, her açılışta yeniden iner | `offline_tile_provider.dart:44-50` |
| P6 | 🟡 DÜŞÜK | city-hero webp'ler `cacheWidth/cacheHeight` olmadan tam boyut decode | `plan_viewer_screen.dart:5638-5644` |
| P7 | 🟡 DÜŞÜK | `LocalPlanCache.listAll()` tüm planları UI thread'de senkron JSON decode; `dirtyPlans()` her çağrıda tekrar | `local_plan_cache.dart:67-81, 112-113` |
| P8 | 🟡 DÜŞÜK | Soğuk açılışta `Env.load` + `Supabase.initialize` + `Telemetry.initialize` hep `await` — ilk kare gecikir | `main.dart:24-78` |

**Öneri (öncelikli):** Optimizasyon pipeline'ının tamamını `compute()`/isolate'e taşı. `Trip` seri hale getirilmesi yerine copyWith zinciri veya isolate sınırında tek transfer kullan. Matris cache'ini provider'a bağla.

---

## 5. Çevrimdışı / Ağ Dayanıklılığı

| # | Ciddiyet | Bulgu | Konum |
|---|---|---|---|
| O1 | 🔴 YÜKSEK | `connectivity_plus` **deklare ama hiç import edilmemiş** → `syncDirty()` asla tetiklenmiyor; çevrimdışı düzenleme `dirty=true` kalıyor, geri bağlanınca otomatik push YOK | `pubspec.yaml:28`, `plans_repository.dart:265` (çağrı yok) |
| O2 | 🔴 YÜKSEK | Harita offline'da boş grid; `errorTileCallback` hiçbir harita ekranında tanımlı değil → hata sessiz | `offline_tile_provider.dart:1-6`, `day_map_screen.dart:212-217` |
| O3 | 🟠 ORTA | Global "çevrimdışısınız" bildirimi yok; `offlineHint` ölü kod (ağ hatası `listLocal()`'a yutulduğu için error dalı hiç tetiklenmiyor) | `plans_list_screen.dart:76-80`, `plans_repository.dart:197-199` |
| O4 | 🟠 ORTA | Hava durumu disk cache'siz; yeniden açılışta offline'ta "veri yok" | `weather_screen.dart:62-65`, `weather_service.dart:118-138` |
| O5 | 🟠 ORTA | ML Kit dil modeli ilk indirmede ağ yoksa otomatik retry yok (crash yok, ama elle yeniden deneme gerek) | `offline_translation_mlkit.dart:36-40`, `offline_translator_card.dart:117-124` |
| O6 | 🟡 DÜŞÜK | Ağ görselleri disk'te cache'lenmiyor (`cached_network_image` yok); offline'ta önceden görülen yer resimleri kaybolur | `place_image_resolver.dart:24-53`, `place_detail_sheet.dart:1099` |

**Not — iyi olanlar:** Döviz kuru (12h taze cache + default'a düşme), geofence (arka planda duraklatma, pil dostu), `device_steps` (ağsız), `exchange_rate_store` (stale-tolerant) sağlam.

**Kullanıcı gibi test notu:** "İnterneti kes" senaryosunda ana akışların çoğu **çökmeden** çalışıyor (planlar yerel cache'ten açılır, çeviri modeli hazırsa çalışır), ancak kullanıcıya "şu an çevrimdışısınız" dendiği tek yer yok; harita sessizce boş kalıyor ve dirty planlar geri gelince sessizce bekliyor. Bu, "sessiz düşme" kalıbının ürün düzeyinde bir eksikliği.

---

## 6. Apple Standartları / HIG Uyumu

| Durum | Bulgu |
|---|---|
| ✅ | Apple Sign-In entitlement (`com.apple.developer.applesignin=Default`) + nonce SHA-256 akışı doğru (raw→Supabase, hashed→Apple) |
| ✅ | `PrivacyInfo.xcprivacy` kapsamlı: e-posta, user content, User ID, Product Interaction, CrashData, PerformanceData; tracking=false; UserDefaults/FileTimestamp/SystemBootTime/DiskSpace reason'ları dolu |
| ✅ | `Info.plist` izin açıklamaları TR + `en.lproj`/`tr.lproj` `InfoPlist.strings` |
| ✅ | `ITSAppUsesNonExemptEncryption=false` (export compliance) |
| ✅ | Apple butonu yalnız iOS/macOS'ta gösteriliyor (`auth_screen.dart:97-100`), `dart:io` web'e sızmıyor |
| ⚠️ | Sistem yazı boyutu (`textScaler`) test edilmemiş (HIG maddesi) |
| ⚠️ | iPad gerçek cihaz testi yok |
| ⚠️ | Branded launch screen / son görsel cila kararı açık |

---

## 7. Login / Google / Apple Sign-In Doğruluk

| Akış | Durum | Not |
|---|---|---|
| Email + şifre | ✅ | Form validation (e-posta/≥6), `_friendlyAuthError` TR/EN dostane hata eşlemesi (`invalid_credentials`, `email_not_confirmed`, `user_already_exists`, `weak_password`, `rate_limit`, `network`) |
| Google OAuth | ✅ kod | `signInWithOAuth` + deep link `io.supabase.rotori://login-callback/` + `CFBundleURLTypes` + `LSApplicationQueriesSchemes` doğru. **Ama** Supabase'te Google production callback + client ID doğrulanmalı (P0 checklist). |
| Apple Sign-In | ✅ kod | Native token akışı; nonce üretimi kriptografik güvenli (`Random.secure`); cancel sessiz; hata TR mesajlı. |
| Router auth-guard | ✅ | `resolveAuthRedirect` + `_AuthRefreshListenable`; session'ı doğrudan SDK'dan okuma (race condition bilinçli çözülmüş, `router.dart:48-52`). |
| Session kalıcılığı | ✅ | `supabase_flutter` otomatik session persist; `authStateProvider` stream → router yönlendirme. |
| Hesap silme | ❌ | Backend var, UI yok (bkz. P0-1). |
| Email onayı | ❌ | Kapalı (bkz. P0-2). |
| Şifre sıfırlama akışı | ⚠️ | Kodda `resetPassword`/forgot-password ekranı **görünmüyor** — prod checklist'inde test edilmeli; yoksa eklenmeli. |

**Güvenlik doğrulaması:**
- `delete_current_user()` RPC (`supabase/migrations/0004_delete_current_user_rpc.sql`): `security definer` + `auth.uid()` null-check + `revoke`/`grant execute to authenticated` → kullanıcı yalnızca kendi kaydını silebilir. ✅ (Not: migration repo'da mevcut; prod'a uygulandığı doğrulanmalı.)
- `env.json` / `.env` / Sentry anahtarları **git'te yok** (doğrulandı). ✅
- Sentry: `sendDefaultPii=false`, `attachScreenshot=false`, `attachViewHierarchy=false`, `enableUserInteractionBreadcrumbs=false`. ✅
- Telemetri: rota JSON kendi Supabase'ine gider (üçüncü taraf değil); uçuş/otel/bilet/not/e-posta/GPS içermediği prod'da doğrulanmalı.

---

## 8. Test Kapsamı ve Eksik Testler

### Mevcut (iyi)
- 540+ birim/widget testi **geçiyor** (exit 0). Alanlar: domain (route optimizasyon, maliyet, bütçe, itinerary, checklist…), veri katmanı (cache, FX, weather, offline matrix), widget (viewer ekranları, plan akışı, canlı kur tarayıcı).
- `flutter analyze` temiz, `strict-casts/inference/raw-types` açık.

### Kırık (QA senaryo koşucusu — taze koşum, 88/95)
`qa/latest-run.json` (2026-08-17 03:16) → **7 fail**: `s04, s13, s14, s15, s20, s23, s85`.
- `s13` — "QA Test Trip" metni beklenmedik yerde bulundu.
- `s14` — geçmiş gün kartı opaklığı 0.6 değil.
- `s15` — beklenen ikon bulunamadı (`IconData(U+0E67C)`).
- `s20` — "Japon Gecesi" metni bulunamadı.
- `s04, s23, s85` — `Expected: true, Actual: false` (içerik/durum iddiası).
- **Muhtemel kök neden:** `apple-design-polish` branch'indeki viewer/planner tema ve içerik değişiklikleri sonrası bayat test beklentileri. Bu senaryolar güncellenmeli veya gerçek regresyon ise düzeltilmeli.

### Eksik test alanları
1. **Auth akışı widget testleri sınırlı** — Google OAuth E2E yok (native, doğal), şifre sıfırlama akışı testi yok.
2. **Çevrimdışı senkron testi yok** — `syncDirty`/connectivity geri-bağlanma testi (kod zaten eksik, O1).
3. **Performans benchmark testi yok** — "plan üretimi ≤ 300 ms" hedefi (`CLAUDE.md` §8) otomatik doğrulanmıyor.
4. **A11y / textScaler testi yok** — sistem yazı boyutu büyütülünce taşma olup olmadığı test edilmiyor.
5. **iPad / çoklu cihaz widget testi yok.**
6. **`integration_test/` gerçek cihazda koşulmamış** — yalnızca scenario_runner var.
7. **Test sırasında 45 adet non-fatal `Codec failed to produce an image` uyarısı** — widget testlerindeki placeholder/network görsellerinin decode edilememesi. Testler geçiyor ama temizlenmeli (muhtemel `Image.memory`/`Image.network` test fixture'ları).

---

## 9. Bonus — Android (Play Store paralel eksikler)

App Store hedefi olsa da aynı kod tabanı Play'e de çıkacaksa:

- 🔴 **`INTERNET` izni release manifest'te yok** — yalnızca `src/debug` ve `src/profile` manifest'lerinde (`android/app/src/main/AndroidManifest.xml`). Release build'de Supabase ağı çalışmaz.
- 🔴 **`POST_NOTIFICATIONS` izni yok** — Android 13+ bildirim izni istenemez (reminder özelliği var).
- 🟠 **Release imzalama debug anahtarıyla** (`build.gradle.kts:31-33`).

---

## 10. Öncelikli Aksiyon Listesi (Sıralı)

1. **P0-1** Hesap silme akışını UI'a bağla (drawer + onay + yönlendirme).
2. **P0-2** Supabase "Confirm email" aç.
3. **P0-3** Xcode/device-support engelini çöz → gerçek cihaz smoke test.
4. **P0-5** Signing & Capabilities + App Store Connect kaydı tamamla.
5. **P0-4** Final indirme boyutunu ölç, 60 MB hedefine yaklaştır.
6. **P1** `connectivity_plus`'ı gerçekten bağla → `syncDirty` otomatik tetik + global offline bildirimi (O1, O3).
7. **P1** Optimizasyonu `compute()`/isolate'e taşı (P1, P2).
8. **P1** StoreKit/IAP kararı: paywall-only mi, gerçek satın alma mı (Beta Review Notes'ta belirt).
9. **P1** 7 kırık QA senaryosunu düzelt/güncelle (s04, s13, s14, s15, s20, s23, s85).
10. **P1** Şifre sıfırlama akışı + harita offline bildirimi.
11. **P2** Widget scope kararı; yasal sayfalar; iPad testi; harita sağlayıcı SLA'sı.

---

## 11. Test Türü Matrisi (QA perspektifi)

| Test Türü | Kapsam | Sonuç |
|---|---|---|
| Statik analiz | `flutter analyze` (strict) | ✅ Temiz |
| Birim (domain) | rota, bütçe, itinerary, checklist, parser | ✅ Yeşil |
| Widget | viewer/planner ekranları, kur tarayıcı | ✅ Yeşil |
| QA senaryo (UI regresyon) | 95 senaryo | ⚠️ 7 fail |
| Entegrasyon (E2E) | `integration_test/` | ⚠️ gerçek cihazda koşulmadı |
| Güvenlik | RLS, RPC, secret sızıntısı, Sentry PII | ✅ (hesap silme UI hariç) |
| Performans | optimize süresi, soğuk açılış, bellek | ❌ UI-thread blok + benchmark yok |
| Çevrimdışı/ağ | uçak modu, reconnect | ⚠️ çökmez ama sessiz; senkron yok |
| Uyumluluk | iPad, küçük ekran, textScaler | ❌ test edilmedi |
| Erişilebilirlik | kontrast, font ölçeği | ⚠️ kısmen (kod), test yok |
