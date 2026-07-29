# ARCHITECTURE.md — Rotori

> Bu belge **şu anki** mimariyi anlatır. Kod değiştikçe güncellenir.
> Kalıcı kurallar için `CLAUDE.md`, günlük iş için `CURRENT_TASK.md`.

Son güncelleme: **2026-07-30** (tanıtım sitesi yerel medya asset'leri).

---

## 1. Yüksek Seviye Görünüm

```
                         ┌───────────────────────────┐
                         │   Supabase (Tokyo, RLS)   │
                         │   • auth · plans · prof.  │
                         └───────────┬───────────────┘
                                     │  supabase_flutter
                                     ▼
┌───────────────────────┐    ┌───────────────────────┐    ┌───────────────────┐
│   Flutter mobil app   │    │  React apps (legacy)  │    │  Marketing site   │
│   mobile/ (primary)   │    │  apps/planner+viewer  │    │  website/         │
│   iOS · web-preview   │    │  Vite + workspaces    │    │  self-contained   │
└───────────┬───────────┘    └───────────┬───────────┘    └───────────────────┘
            │                            │
            ▼                            ▼
   shared_preferences /            data/trips/*.json
   flutter_cache_manager           (statik seyahat verisi)
```

## 2. Modül Sınırları (mobil)

| Modül | Sorumluluk | Bağımlılıklar |
|---|---|---|
| `lib/domain/` | Saf iş kuralları — plan üretimi, geofence matematiği, city_places, itinerary. | Sıfır Flutter/Supabase importu. Yalnızca `dart:core`. |
| `lib/data/` | Store'lar (Riverpod state + kalıcılık), Supabase repo katmanı, OCR köprüsü. | `flutter_riverpod`, `shared_preferences`, `supabase_flutter`, ML kit. |
| `lib/core/` | l10n, router, Supabase client init. | Flutter + go_router. |
| `lib/features/*` | UI ekranlar + widget'lar. `domain/data`'yı kullanır; asla `domain` içine kaçırılmamış Supabase koymaz. | Flutter widget katmanı. |
| `lib/theme.dart` | Renk paleti + tipografi. | Yalnızca Material. |

**Bağımlılık grafı yönü (yukarıdan aşağı, tersine yasak):**

```
features → data → domain
   │        │
   └────────┴──→ core (l10n, router)
```

## 3. Feature Klasörleri

```
mobile/lib/features/
├─ auth/                     # login, signup, apple, google, delete-account
├─ notifications/            # local notifications permission + scheduler
├─ planner/
│  ├─ planner_screen.dart    # 8 adımlı stepper shell
│  └─ steps/                 # welcome → journey → explore → title
│                            # → hotels → food → plan → publish
├─ plans/
│  ├─ plan_providers.dart    # planları çeken/senkronlayan Riverpod
│  ├─ plans_list_screen.dart # kaydedilmiş planlar
│  └─ plan_viewer_screen.dart# aktif plan görüntüleyici (viewer entry)
├─ reminders/                # bilet hatırlatmaları
├─ viewer/
│  ├─ budget_screen.dart, checklist_screen.dart, compass_screen.dart,
│  │  day_map_screen.dart, japanese_phrases_screen.dart,
│  │  must_know_screen.dart, pre_departure_checklist_screen.dart,
│  │  reward_map_screen.dart, weather_screen.dart, gps_sim_screen.dart
│  ├─ geofence_service.dart  # GPS akışı → geofence + XP
│  ├─ offline_tile_provider.dart  # OSM tile cache köprüsü
│  ├─ home_widget_hook.dart  # iOS App Group köprüsü (web no-op)
│  ├─ sakura_overlay.dart    # dekoratif overlay
│  ├─ viewer_theme.dart      # viewer'a özel renk overrid'leri
│  └─ widgets/               # paylaşılan viewer bileşenleri
└─ shared/
   └─ place_detail_sheet.dart# tüm ekranlarda kullanılan yer detay sheet'i
```

## 4. Routing

- **Flutter mobil:** `lib/core/router.dart` içinde `go_router`. Provider adı
  `routerProvider`. Auth guard router seviyesinde; oturum yoksa `/auth`'a
  yönlendirir. Preview modu (`preview_main.dart`) router'ı bypass'lar.
- **Web (legacy planner + viewer):** `apps/*/vite.config.ts` üstünden Vite
  route'ları; `docs/PHASE2-ROUTING.md` içinde nginx örneği.

## 5. State Management Akışı

- **Kaynak:** `Riverpod` provider'ları. State genellikle `AsyncNotifier`
  (Supabase-backed) veya `Notifier` (yerel).
- **Kalıcılık:** `shared_preferences` — dil, tema, oturum ipuçları, plan cache.
- **Servis→UI:** UI `ref.watch()` ile Provider'ı dinler. Servis Supabase'e
  yazar, ardından provider `invalidate()` edilir.
- **Optimistic UI** planner adımlarında bilinçli kullanılır (kullanıcı
  yazdıkça yerelde tutulur, publish adımında senkronlanır).

## 6. Domain Katmanı (özet)

Pure Dart dosyaları — `flutter test` altında hızlı çalışır.

| Dosya | Amaç |
|---|---|
| `itinerary_generator.dart` | Plan iskeletini üretir (şehir + gün sayısı → gün başlıkları + yer taslakları). |
| `fill_empty_days.dart` | Boş günleri şehir profiline göre otomatik doldurur. |
| `rules.dart` | Genel plan kısıtları (tempo, aile ile gitme kuralları vb.). |
| `city_transfers.dart` | Şehirlerarası ulaşım süreleri (Shinkansen tabloları). |
| `city_places.dart` | Şehir başına yer katalogu (LText'li). |
| `place_coords.dart` | Yer adı → lat/lng çözümü (geofence + harita için). |
| `place_guide.dart` | Uzun-form yer rehberi metinleri (LText). |
| `place_image_resolver.dart` | *(yeni)* Yer adı → asset görsel çözümleyicisi. |
| `day_schedule.dart` | *(yeni)* Gün içi zaman-çizelgesi hesaplaması. |
| `day_optimizer.dart` | Aynı gün içi yerlerin en verimli sırasını arar. |
| `geofence.dart` | Konum akışı üzerine geofence matematiği. |
| `japan_suggestions.dart` | Ülke düzeyi öneriler (mevsim / bölge). |
| `budget.dart` | Bütçe kırılım/mantık. |
| `dietary.dart` | Diyet filtreleri. |
| `explore.dart` | Ödül haritası mantığı. |
| `types.dart` | Domain modelleri — `packages/shared/src/types.ts` ile aynalıdır. |
| `localized_text.dart` | `LText(tr, en)` ve `.of(lang)` yardımcısı. |

## 7. Data Katmanı (özet)

- **`supabase_client.dart`** — tekil client, `Env` üzerinden.
- **Store'lar** (Riverpod'la wrap'lı):
  - `language_store.dart` — aktif dil (`AppLang.tr | .en`), `app:lang` anahtarında kalıcı.
  - `plan_store.dart` / `plans_repo.dart` — Supabase `plans` tablosu ile senkron.
  - `user_stats_store.dart` — XP, rozetler.
  - `ticket_ocr.dart` — mobilde ML Kit köprüsü, web'de conditional import ile no-op.
- **Yerel plan cache:** `shared_preferences` içinde JSON serileştirme. Ağ
  yoksa uygulama son senkronla açılır.

## 8. Auth

Katmanlar:

1. `Supabase.auth` (email+password, Google OAuth, Apple).
2. `authProvider` (Riverpod) — oturum state'ini dinler.
3. Router guard: oturum yoksa `/auth`.
4. Preview entry (`preview_main.dart`) auth-less — QA/tasarım için.

## 9. Yerel Depolama & Çevrimdışı Destek

- **`shared_preferences`** — dil, tema, kullanıcı istatistiği, plan snapshot.
- **`flutter_cache_manager`** — OSM harita karoları (iOS/Android). Web'de
  `kIsWeb` kapısı; `NetworkImage`'e düşer.
- **Home widget (iOS)** — App Group üzerinden `UserDefaults`'a yazar; web/Android'de no-op.
- **Bildirim programı** — yerel `timezone` verisi ile `flutter_local_notifications`.

Kural: uçakta çalışmalı. Bir feature yeni bir *zorunlu* ağ bağımlılığı
getirecekse mimari karar `DECISIONS.md`'ye yazılır.

## 10. API Katmanı

- Yalnızca **Supabase RPC** ve tablo erişimi (repo katmanı).
- Faz 2 için `apps/api/` altında Express stub (`/api/trips/*`) — canlı değil.
- Third-party ağ çağrıları: **Open-Meteo** (hava — anahtar yok), **OSM tile**
  (harita — anahtar yok). Sadece bu ikisi.

## 11. Background Jobs

- Şu an server-side job yok. `flutter_local_notifications` uygulama içi zamanlanan
  yerel işleri sürer (bilet açılış hatırlatmaları).

## 12. Test Mimarisi

- **Konum:** `mobile/test/` — Flutter test paketi.
- **Odak:** domain katmanı (saf Dart) + kritik core sınıfları.
- **Yeni test dosyaları:** `mobile/test/domain/day_schedule_test.dart`,
  `mobile/test/domain/place_image_resolver_test.dart`, `mobile/test/core/*`
  (çalışan diff'te). Bunlar F2.0 test regresyonlarını karşılıyor (`70c82d2`).
- **Komut:** `cd mobile && flutter test`.
- **CI:** Şu anda GitHub Actions henüz kurulu değil (aday karar — `DECISIONS.md`).
- **Web QA:** `apps/planner` altında Playwright benzeri kurulum yok; F1'de QA
  dashboard'u eklendi (`888feb2`, `13969b9`) — 110 senaryo · 95 otomatik %100 pass.

## 13. Web Uygulamaları (özet)

```
apps/
├─ api/         Express, port 3920 (stub)
├─ planner/     React + Vite (7-adım planner). npm run dev:planner → 5174
├─ viewer/      React + Vite PWA rehber.       npm run dev:viewer  → 5180
packages/
└─ shared/      TypeScript tipler + zod + kurallar. Vite build.
```

`npm run build` → `dist/index.html + dist/viewer + dist/planner + data/`.

## 14. Deploy Yolu

- **Web:** `npm run build` → `dist/` → nginx/pi rsync (bkz. `README.md`).
- **Mobil:** Xcode → App Store Connect (F1 hazırlığı `11f3541`).
- **Site:** `website/index.html` + `website/img/` + `website/audio/` birlikte
  versiyonlanır ve statik host'a kopyalanır.

## 15. Bilinen Yumuşak Noktalar

- `apps/api` yalnızca stub — Faz 2 yeniden ele alınacak.
- Google OAuth iOS bundle'da uçtan uca doğrulanmalı (`233a57e` genel akış geldi).
- Home widget yalnızca iOS'ta; Android widget yok.
- Test kapsamı domain'de yüksek, UI'da düşük — bilinçli.
