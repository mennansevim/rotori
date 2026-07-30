# CLAUDE.md — Rotori (japan-trip) Permanent Project Memory

> Bu belge projenin **kalıcı hafızasıdır**. Nadiren değişir. Kod, mimari veya
> ürün yönü değiştiğinde önce burası — sonra kod güncellenir.

---

## 1. Ürün

**Rotori** — Japonya odaklı, çevrimdışı çalışan, kişiye özel seyahat planlayıcı
ve rehber. Marka önce "Tabi" (旅) olarak öneriliydi, 2026-07 civarında
**Rotori** olarak rebrand edildi (bkz. DECISIONS.md · `360e5ae`).

- **Slogan:** "Sürpriz yok, plan var." (site + uygulama tutarlı)
- **Vizyon:** Kullanıcı Japonya'ya inmeden önce her günü dakikası dakikasına
  planlanmış, indikten sonra da GPS ile keşif yapan bir seyahat ekibi hissi.
- **Hedef kullanıcı:** İlk kez Japonya'ya giden Türk gezginler (birincil);
  planı ekiple paylaşmak isteyen deneyimli gezginler (ikincil).
- **İş hedefi:** App Store'da premium (ancak ücretsiz reklamsız MVP) bir seyahat
  yardımcısı yayınlamak; ilerideki fazlarda çoklu ülke desteği + sosyal katman.

## 2. Yüzeyler (Product Surfaces)

| Yüzey | Yol | Amaç |
|---|---|---|
| Mobil uygulama | `mobile/` | **Birincil ürün** — Flutter, iPhone-first. Supabase auth + plan senkronu. |
| Tanıtım sitesi | `website/index.html` | Apple-kalite, TR/EN, tek dosya self-contained landing. |
| Klasik rehber | `index.html` (kök) + `apps/viewer/` | Statik JSON tabanlı PWA rehber (eski nesil). |
| Planner web | `apps/planner/` | 7 adımlı React planlayıcı (mobil öncesi nesil, hâlâ demoya açık). |
| API stub | `apps/api/` | Faz 2 çoklu kullanıcı için Express stub — canlı değil. |
| Backend | Supabase `vsclzcillbveregzsgmj` (Tokyo) | Auth + `plans` + `profiles` + RLS. |

> **Enerji dağılımı:** Bugün asıl geliştirme `mobile/` içindedir. `apps/*`
> ve kök `index.html` bakım/demo modundadır.

## 3. Tech Stack

### Mobil (`mobile/`)

- **Flutter** ≥ 3.24, Dart SDK 3.4+
- **State:** `flutter_riverpod` ^2.5 (providers · `..._store.dart` konvansiyonu)
- **Routing:** `go_router` ^14
- **Backend:** `supabase_flutter` ^2.5 — env `mobile/env.json` (**gitignore**).
- **i18n:** Manuel `lib/core/l10n.dart` — `AppLang.tr | .en`, ~800+ anahtar +
  büyük içerik için `LText(tr, en)` (bkz. `domain/localized_text.dart`).
- **Harita:** `flutter_map` + OSM raster tile (API key yok) + offline tile
  cache (`flutter_cache_manager`, web'de kIsWeb ile no-op).
- **Rota optimizasyonu:** Saf Dart yönlü `RouteMatrix` +
  `BeamSearchItineraryOptimizer` (beam width 6, local improvement, dört
  profil). Gerçek ulaşım sağlayıcısı yalnızca backend/Edge Function gateway'i
  arkasından çağrılır; API anahtarı mobil uygulamaya girmez. AI rota
  hesaplamaz ve varsayılan akışta çağrılmaz.
- **GPS:** `geolocator` + `lib/features/viewer/geofence_service.dart` —
  dwell 600 s, grace 120 s, radius+min(accuracy, 80) eşiği.
- **OCR:** `google_mlkit_text_recognition` — yalnızca mobil, web'de conditional
  import ile izole (`data/ticket_ocr.dart`).
- **Bildirim:** `flutter_local_notifications` + `timezone` — bilet açılış
  hatırlatmaları; web'de no-op.
- **Auth:** email/password + `sign_in_with_apple` (iOS/macOS) + Google OAuth.
- **iOS ek:** Home-screen widget App Group üzerinden (`home_widget_hook.dart`).

### Web (`apps/*`)

- React + Vite workspaces (`npm workspaces`). Paylaşımlı domain: `packages/shared`
  (TypeScript + zod). Node ≥ 20 varsayılır.
- `apps/api` Express, port 3920 — Faz 2 API stub.

### Backend

- **Supabase** ap-northeast-1 (Tokyo), owner `mennansevim@gmail.com`.
  Migrasyonlar `supabase/migrations/` altında: init, social, pre_departure_checklist,
  delete_current_user_rpc.
- **RLS** her tabloda açık.

## 4. Kod Konvansiyonları

- **Dil:** Kod ve yorumlar Türkçe; kullanıcı yüzeyleri TR + EN (i18n zorunlu).
- **Naming:**
  - Dart: dosya `snake_case.dart`, sınıf `PascalCase`, üye `camelCase`.
  - Riverpod provider: `xxxProvider` (ör. `appLangProvider`, `routerProvider`).
  - Store: `..._store.dart` (kalıcı state, ör. `language_store.dart`).
  - Domain: pure Dart, Flutter import etmez.
- **Yorumlar:** Yalnızca *neden* açık değilse yazılır; *ne* yaptığını isim söyler.
- **String edebiyatı:** UI'da hardcoded metin yasak — l10n anahtarı veya `LText`.
- **Test:** `mobile/test/` altında, `flutter test` sürer. Yeşil bar zorunlu.

## 5. Klasör Sorumlulukları (mobil)

```
mobile/lib/
├─ main.dart               # gerçek app entry (Supabase init, DevicePreview)
├─ preview_main.dart       # QA/tasarım preview entry (auth-less)
├─ env.dart                # --dart-define-from-file=env.json köprüsü
├─ theme.dart              # AppTheme.dark, japanDark #0A0A0F + pembe→mor
├─ core/                   # l10n, router, supabase_client
├─ data/                   # store'lar, ticket_ocr, language_store, ...
├─ domain/                 # pure Dart iş kuralları — Flutter yok; route matrix
│                          # + deterministic itinerary optimizer burada
├─ features/
│  ├─ auth/                # login / signup / apple / google
│  ├─ planner/steps/       # 8 adımlı planner (welcome→publish)
│  ├─ plans/               # plan listesi + viewer
│  ├─ viewer/              # gün haritası, geofence, sakura, bileşenler
│  ├─ notifications/       # bildirim izin + planlama
│  ├─ reminders/           # bilet hatırlatma
│  └─ shared/              # ortak widget'lar, place_detail_sheet
└─ theme.dart
```

## 6. Mimari İlkeler

1. **Domain saf tutulur.** `mobile/lib/domain/` içindeki dosyalar `flutter/*`
   veya `supabase_flutter` import etmez — böylece unit-test'lenebilir.
2. **Çevrimdışı-öncelikli.** Uçakta / dolaşımda çalışmalı: OSM tile cache,
   `shared_preferences` yerel plan, `LText` gömülü içerik.
3. **Kimlik doğrulaması ürünün önünde bariyer değil.** Preview/QA
   ekranları auth'suz açılır; yalnızca senkron gerektiği anda oturum sorulur.
4. **Web türev bir hedef.** `--kIsWeb` gate'i ile paketler graceful düşer
   (OCR, bildirim, tile cache, home widget). Ana geliştirme mobil.
5. **Marka dili tek yerden.** Metinler `l10n.dart` / `LText`, renk `theme.dart`,
   ikon set `lucide_icons_flutter` — emoji sadece bilinçli semantik yerlerde.

## 7. Hata Yönetimi Felsefesi

- **Sınır'da yakala, içeride güven.** Ağ, dosya, izin, OCR — try/catch sarılır
  ve `Result<T, E>` yerine kullanıcıya *anlamlı, iki dilli* bir toast döner.
- **Sessiz düşme yalnızca web-only paketler için** (bkz. `home_widget_hook.dart`).
- **assert / throw** yalnızca invariant ihlali için — kullanıcı hatası değildir.

## 8. Performans Hedefleri

- İlk açılış → interaktif: **≤ 2 s** iPhone 12 üstünde.
- Plan üretimi (`itinerary_generator` + `fillEmptyDays`): **≤ 300 ms** 13-gün, 4-şehir.
- Harita gün açılışı: cache hit varsa **≤ 250 ms**.
- Uygulama boyutu (iOS release): **≤ 60 MB**.

## 9. Güvenlik Kuralları

- `mobile/env.json`, `.env`, Supabase servis-role anahtarları **repoya girmez**.
- Supabase RLS her tabloda zorunlu (istisna yok).
- Kullanıcı verisinin sunucuda tutulduğu tek yer Supabase. Yerelde sadece plan
  + tercihler; kart/bilet OCR görselleri cihazda kalır, yüklenmez.
- Prod'a çıkmadan önce Supabase Auth "Confirm email" **açılmalı** (şu an test
  için kapalı).

## 10. Apple HIG uyumu (mobil ürün için)

- Safe area her ekranda gözetilir. Cupertino/Material karışımı yasak — Material
  temel, ancak `CupertinoIcons`/`sign_in_with_apple` gibi Apple-native kırıcılar
  bilinçli.
- Sistem yazı boyutu (`textScaler`) test edilmelidir.
- Bildirim ve konum izinleri **kullanım anında** istenir, başlatmada değil.
- App Store meta zorunluluğu: `App-Store-Meta/`, Privacy Policy sayfası
  (`website/privacy.html`), hesap silme akışı (F1'de eklendi · `11f3541`).

## 11. Tanıtım Sitesi Kuralları (`website/`)

- HTML, CSS ve JavaScript `website/index.html` içinde kalır. Büyük medya
  dosyaları (`website/img/`, `website/audio/`) ayrı, yerel ve
  versiyonlanmış asset olarak yayınlanabilir; üçüncü taraf çalışma zamanı
  bağımlılığı eklenmez.
- TR/EN, `data-i18n` anahtar sistemi; `window.__i18nAudit()` eksiklik denetimi.
- Design System v2 devrede (`4578280`) — koyu sinematik, pembe→mor gradyan.
- Yerel servis: `cd website && python3 -m http.server 8091`.

## 12. `run` Kısayolu

- Kullanıcı yalnızca **“run”** dediğinde birincil ürün olan `mobile/` altındaki
  Rotori Flutter uygulaması beklemeden başlatılır.
- Mevcut ve uygun cihaz/simülatör tercih edilir; gerekli gizli değerler yalnızca
  yerel yapılandırmadan okunur ve çıktıda gösterilmez.
- Tanıtım sitesi ancak kullanıcı açıkça “siteyi run” veya eşdeğerini söylediğinde
  yerel web sunucusuyla başlatılır.

## 13. Definition of Done

Bir feature ancak şu koşullar sağlandığında bitmiş sayılır:

- [ ] Kod TR/EN i18n tam — `flutter analyze` 0 error.
- [ ] İlgili domain testleri yeşil (`flutter test`).
- [ ] iPhone gerçek cihazda veya `device_preview` üstünde bir kez elle görülmüş.
- [ ] Yeni bir mimari karar varsa `DECISIONS.md`'ye eklendi.
- [ ] `CURRENT_TASK.md` güncellendi (tamamlandı → tarih damgası).
- [ ] Gerekliyse `ARCHITECTURE.md` yenilendi.
- [ ] Sızıntı: hiçbir gizli anahtar diff'te yok (`git diff` gözden geçirildi).

---

**Değişiklik günlüğü:** Bu dosya her rebrand, tech-stack değişikliği veya
felsefe değişiminde güncellenir. Bir sonraki güncellemeden önce `git log docs/CLAUDE.md`
sürümüne bak.
