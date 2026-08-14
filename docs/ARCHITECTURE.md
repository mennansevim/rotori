# ARCHITECTURE.md — Rotori

> Bu belge **şu anki** mimariyi anlatır. Kod değiştikçe güncellenir.
> Kalıcı kurallar için `CLAUDE.md`, günlük iş için `CURRENT_TASK.md`.
> Rota motorunun ayrıntılı akış ve maliyet notu: `ROUTE_OPTIMIZATION.md`.

Son güncelleme: **2026-08-11** (§19 ücretli çalışma zamanı sağlayıcısı yerine
sürümlü offline Japonya rota paketi eklendi).

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
│ rotori-mobile/(primary)│    │ website/legacy/apps/  │    │ rotori-website/   │
│   iOS · web-preview   │    │  Vite + workspaces    │    │  self-contained   │
└───────────┬───────────┘    └───────────┬───────────┘    └───────────────────┘
            │                            │
            ▼                            ▼
   shared_preferences /            legacy/data/trips/*.json
   flutter_cache_manager           (statik seyahat verisi)
```

> **Monorepo (2026-08-03):** Kök `rotori-app/`. Üç ayak: `rotori-mobile/`,
> `rotori-website/` (+ `legacy/` eski React PWA & build), `rotori-social/`
> (sosyal kaynak kod doğrudan bu dizine taşındı, nested `.git` kaldırıldı). Paylaşılan `docs/`
> ve `supabase/` kökte. Vercel kaldırıldı.

## 2. Modül Sınırları (mobil)

| Modül | Sorumluluk | Bağımlılıklar |
|---|---|---|
| `lib/domain/` | Saf iş kuralları — plan üretimi, geofence matematiği, city_places, itinerary. | Sıfır Flutter/Supabase importu. Yalnızca `dart:core`. |
| `lib/data/` | Store'lar, Supabase repo, OCR köprüsü, rota backend/cache/fallback ve AI review adapter'ları. | `flutter_riverpod`, `shared_preferences`, `supabase_flutter`, ML kit; rota domain abstraction'ları. |
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
rotori-mobile/lib/features/
├─ auth/                     # login, signup, apple, google, delete-account
├─ notifications/            # local notifications permission + scheduler
├─ planner/
│  ├─ data/                  # havayolu ve havalimanı katalogları
│  └─ widgets/               # plan yüzeylerinin ortak seçicileri
├─ plans/
│  ├─ create/                # 3 adım: şehir → tarih → yemek/bütçe
│  ├─ plan_providers.dart    # planları çeken/senkronlayan Riverpod
│  ├─ plan_edit_session.dart # optimistic edit, seri kayıt, rollback + undo
│  ├─ plans_list_screen.dart # kaydedilmiş planlar
│  └─ plan_viewer_screen.dart# aktif plan görüntüleyici (viewer entry)
├─ reminders/                # Premium bilet hatırlatmaları + hazır/özel çoklu ekleme paneli
├─ viewer/
│  ├─ budget_screen.dart, checklist_screen.dart, compass_screen.dart,
│  │  day_map_screen.dart, experience_guide_screen.dart,
│  │  japanese_phrases_screen.dart,
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
- **Tema başlangıcı:** Uygulama kabuğu ve viewer yeni kurulumda aydınlık açılır.
  Viewer `viewer:theme` tercihi varsa onu yükler; böylece mevcut kullanıcının
  koyu veya Sakura tercihi varsayılan değişikliğinden etkilenmez.
- **Servis→UI:** UI `ref.watch()` ile Provider'ı dinler. Servis Supabase'e
  yazar, ardından provider `invalidate()` edilir.
- **Optimistic UI** planner adımlarında bilinçli kullanılır (kullanıcı
  yazdıkça yerelde tutulur, publish adımında senkronlanır).
- **Plan düzenleme:** UI mutasyonları `PlanEditSession` üzerinden
  `PlanScheduleEngine` komutlarına gider. Session komutları sıraya alır,
  sonucu önce ekrana uygular, yerel kayıt başarısız olursa önceki snapshot'a
  döner ve başarılı değişiklikleri undo yığınında tutar.
- Saat ve gün seçiciler motordan gelen uygunluk listesini kullanır. Her
  aktivitenin süresi ile öncesi/sonrasındaki 15 dakikalık tampon görünmez
  biçimde bloke edilir; geçersiz slotlar seçim yüzeyinde gri ve pasiftir.
- Saat değişikliği yalnızca seçilen aktiviteyi sabitler; aynı gündeki sonraki
  aktiviteler 15 dakikalık minimum geçişle yeniden saatlenir. Günler arası
  taşımada hem kaynak hem hedef gün yeniden optimize edilir; hedefte uygun
  slot yoksa komut planı değiştirmeden typed failure döndürür.
- Motor, eski/ithal planda zaten bulunan zaman çakışmasını ilgisiz bir
  düzenlemenin hatası saymaz. Yapısal invariant'lar her zaman zorunludur;
  zaman tarafında yalnızca komutun oluşturduğu yeni veya büyüttüğü çakışma
  reddedilir. Böylece kullanıcı mevcut planı parça parça düzeltebilir.
- **Rota optimizasyon ön izlemesi:** `PlanOptimizationController`,
  `TimelineItem` verisini yeni model kopyalamadan `OptimizationActivity`
  girdisine çevirir. Yönlü rota matrisini repository'den alır, saf Dart
  optimizer'ı çalıştırır ve eski/yeni rota metriklerini state'te sunar.
  Optimize plan yalnızca `confirm()` sonrasında repository'ye yazılır;
  `discard()` kalıcı değişiklik yapmaz.
- Viewer gün kartı controller'ı “Rotayı optimize et” bottom sheet'iyle
  tüketir. Dört tercih profili yeniden hesaplama tetikler; eski/yeni
  ulaşım-yürüyüş-aktarma-maliyet özeti gösterilir. Yalnız açık kullanıcı
  onayı repository, edit session ve home widget snapshot'ını yeniler.
- Onaylanan sonuç, `DayPlan.routeExecutionSnapshot` içinde schema v1 olarak
  saklanır ve günlük timeline durakların arasına tek satırlık, zeminsiz kompakt
  ulaşım satırları yerleştirir. Yeni plan oluşturma akışı normal gezi günlerini
  kayıt öncesinde aynı optimizer + validator hattından geçirir ve snapshot'ı
  baştan üretir. Snapshot henüz yoksa viewer mevcut durak sırasını değiştirmeden
  offline Japonya paketiyle geçici satırlar üretir; bunlar kalıcılaştırılmaz ve
  veri kalitesi model içinde `estimated` olarak korunur.
  Plan sürümü, aktivite hash'i veya matris sürümü uyuşmazsa snapshot
  kullanılmaz. Tahmini ayaklar hat/yön uydurmaz; reliable ayaklar sağlayıcının
  opsiyonel hat/yön bilgisini gösterebilir.
- Şehirlerarası geçiş modu ve ona bağlı bilet, sırasıyla
  `UpdateCityTransition` ve `UpsertTicket` komutlarıyla aynı
  `PlanScheduleEngine` mutasyon hattından geçer. `DayPlan.cityTransition`
  seçimin tek doğru kaynağıdır; timeline'daki `isCityTransition` işaretli
  ulaşım satırı ve moda bağlı gün başlığı bu kaynaktan yeniden türetilir.
  Böylece mod değiştiğinde eski tren/otobüs metni, süre veya rota snapshot'ı
  ekranda kalamaz. İşareti bulunmayan eski planlarda yalnız şehir çiftiyle
  birebir eşleşen transport satırı bir kez geriye uyumlu olarak tanınır.
- Kullanıcı gün içinden etkinlik eklerken “biletim var” seçerse etkinlik ve
  bilet `AddTicketedActivity` ile atomik eklenir. Mevcut yere taranmış bilet
  `AttachTicketToActivity` ile kimlik üzerinden bağlanır; bilet tarihi gerekirse
  etkinliği doğru güne taşır, giriş saati hard constraint olur ve esnek duraklar
  rezervasyonun çevresine yeniden dizilir. Süre ile erken-varış payı hem bilette
  hem timeline öğesinde saklanır; rota optimizer'ı etkinlik bazlı erken-varış
  payını sabit aktivite tamponunun alt sınırı olarak uygular.
- Viewer hamburger menüsü `FittedBox` ile küçültülmez. Sabit marka/gezi başlığı
  altında kaydırılabilir **Yolculuk → Keşfet → Araçlar → Hesap** hiyerarşisi
  kullanır. Keşfet'te Premium fiyat etiketi tarayıcı ve macera rehberi tam
  genişlik vitrin kartlarıdır; hava, bütçe, checklist ve ücretsiz Rotori Eats
  düşük doygunluklu ortak yüzey dilinde iki sütunlu kartlardır. Uçuş/otel
  ayrıntıları açılabilir; ayarlar gruplanmış en az 48 px dokunma alanlı
  satırlardır.
- Plan oluşturulduktan sonra eklenen uçuş bilgileri alan değişiminde otomatik
  kaydedilmez. Form yerel bir plan taslağı düzenler; alttaki tek “Kaydet”
  uçuş bacaklarını ve yalnız varış/dönüş günlerini atomik yeniler, aradaki
  manuel gün düzenlemelerini korur. Başarı dialog'undan sonra viewer güncel
  plan sonucunu doğrudan edit session'a alır, drawer'ı açar ve uçuş
  akordiyonunu genişletir.

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
| `experience_guides.dart` | USJ, Tokyo Disney parkları ve teamLab mekânları için iki dilli bilet, süre, gün akışı, deneyim ve ipucu içeriği. |
| `booking_windows.dart` | Shinkansen, Disney, USJ ve teamLab için resmî kural/planlama hedefi ayrımlı satış pencereleri; plan taraması ve manuel hatırlatıcı preset kataloğu. |
| `ticketed_activity.dart` | USJ/Disney/teamLab ve genel biletli etkinlikler için süre, erken-varış ve tam-gün başlangıç varsayılanları. |
| `place_image_resolver.dart` | *(yeni)* Yer adı → asset görsel çözümleyicisi. |
| `day_schedule.dart` | *(yeni)* Gün içi zaman-çizelgesi hesaplaması. |
| `plan_schedule_engine.dart` | Immutable plan düzenleme komutları, sabit aktivite politikası, 15 dakikalık tampon/slot uygunluğu, çakışma/gün sınırı validasyonu, şehir geçişi/bağlı bilet, biletli etkinlik kimlik bağlantısı ve etkilenen günlerin yeniden zamanlanması. |
| `day_optimizer.dart` | Aynı gün içi yerlerin en verimli sırasını arar. |
| `route_matrix.dart` | Yönlü kapıdan kapıya rota matrisi, yedi ulaşım modu, profil/tercih ve repository abstraction'ı. |
| `itinerary_optimizer.dart` | Beam search (varsayılan width 6), artımlı rota state'i, hard feasibility pruning, local swap/move ve dört profil için maliyet fonksiyonu. |
| `route_execution.dart` | Optimizer bacaklarını kullanıcıya dönük modele çevirir; schema v1 kalıcı route snapshot serileştirmesi ve eşleşme/geçersizleştirme sözleşmesini taşır. |
| `ai_route_review.dart` | AI'ın rotayı değiştirmeden yalnızca yapılandırılmış açıklama/denetim yapabileceği politika, bütçe ve çıktı sözleşmeleri. |
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
- Plan cache'i yerelde dirty iken realtime Supabase satırı bu snapshot'ı
  ezmez. Edit komutları cihaz içinde seri kaydedilir; bağlantı geldiğinde
  repository mevcut dirty snapshot'ı sunucuya taşır.
- **Rota matrisi:** `route_matrix_remote.dart` API anahtarı kabul etmeyen
  `RouteMatrixBackendGateway` sınırını ve normalize sonuç doğrulamasını taşır.
  `route_matrix_resolution.dart` taze cache → birincil sağlayıcı → alternatif
  sağlayıcı → stale/estimated cache → typed unavailable sırasını uygular.
- **Varsayılan taşıyıcı:** `offline_japan_route_matrix.dart`, çalışma zamanı
  API çağrısı yapmadan şehir profili, semt/istasyon kümeleri, yön, gün türü,
  zaman bandı ve küratörlü özel bağlantılardan yürüyüş, toplu taşıma ve taksi
  alternatifleri üretir. Sonuçlar açıkça `estimated` ve sürümlüdür; bilinmeyen
  hat/peron/yön bilgisi uydurulmaz.
- **Rota cache:** Koordinatları dört ondalığa yuvarlayan, yönü koruyan ve
  mod/gün tipi/zaman dilimi/profil/sağlayıcıyı anahtara katan cache
  sözleşmeleri `route_matrix_cache.dart` içindedir. İlk sürüm bellek içidir.
- **AI review:** Gerçek bağlantı Supabase `review-route` Edge Function
  sınırındadır; istemci model anahtarı taşımaz. LLM deterministik rotadan sonra
  yalnız mevcut durakların sıra adayını üretir. En karmaşık en fazla üç gün
  çağrıya girer ve yanıt strict JSON Schema ile sınırlandırılır. Aday doğrudan
  kalıcılaşmaz: `PlanScheduleEngine` üzerinden uygulanır, yalnız etkilenen
  günlerde beam aramasına yumuşak sıra ipucu olur ve aynı ilk-plan optimizer +
  bağımsız validator hattında yeniden hesaplanır. Profil-ağırlıklı gerçek rota
  objective skoru deterministik tabanı en az %2 geçerse kabul edilir. Kabul
  edilen aday yeni `RouteExecutionSnapshot` üretmek zorundadır; hata, timeout,
  eksik snapshot veya skor kazancı yoksa taban rota aynen korunur. Aynı kanonik
  istek kısa ömürlü cache ile tekrar modele gönderilmez; prompt/model sürümü
  cache anahtarının parçasıdır.

## 8. Auth

Katmanlar:

1. `Supabase.auth` (email+password, Google OAuth, Apple).
2. `authProvider` (Riverpod) — oturum state'ini dinler.
3. Router guard: oturum yoksa `/auth`.
4. Preview entry (`preview_main.dart`) auth-less — QA/tasarım için.

## 8b. Abonelik ve Yetkilendirme (Entitlement) — TASARIM

> **Durum: tasarım.** Kod henüz yazılmadı (Faz 1 —
> `CURRENT_TASK.md`). Ürün/fiyat kararı: `MONETIZATION_PLAN.md`.
> Bu bölüm koddan **önce** yazıldı; uygulama buna uyar, sapma olursa
> önce burası güncellenir.

### 8b.1 Mevcut durumdaki güvenlik açığı — Faz 1'de kapatılacak

`0008_daily_scans.sql` içindeki `is_premium()`, yetkiyi
`auth.users.raw_user_meta_data->>'premium'` alanından okuyor. **Bu alan
kullanıcının kendisi tarafından yazılabilir** (`auth.updateUser({data: ...})`),
dolayısıyla yetkilendirme kararı için kullanılamaz. Şu an tarama kotasını
(free 10 / premium 100) herhangi bir kullanıcı kendi metadata'sını
güncelleyerek aşabilir.

Yayınlanmış kullanıcı olmadığı için fiili istismar riski yok, ama
**Faz 1'in ilk işi bu fonksiyonu tablo tabanlı hale getirmektir.**
`raw_user_meta_data` yetkilendirmede hiç kullanılmaz; gerekirse yalnızca
UI hızlandırması için `raw_app_meta_data` (kullanıcı yazamaz) kullanılabilir,
ama **karar her zaman tablodan** verilir. İki kaynağa yazmak drift üretir.

### 8b.2 Üç tablolu şema

Tek tablo yetmiyor çünkü Apple'ın üç ayrı kimliği ve üç ayrı yaşam döngüsü var:

| Tablo | Birincil kimlik | Rolü |
|---|---|---|
| `subscription_entitlements` | `original_transaction_id` **UNIQUE** | **Güncel durum.** Abonelik yaşam döngüsü boyunca tek satır; yenilemede güncellenir |
| `app_store_transactions` | `transaction_id` **UNIQUE** | **Değişmez işlem geçmişi.** Her satın alma ve her yenileme yeni satır; gerçek replay koruması burada |
| `app_store_notifications` | `notification_uuid` **UNIQUE** | **Bildirim idempotency'si.** Aynı bildirim tekrar gelirse iki kez işlenmez |

**Neden karıştırılmamalı:** `original_transaction_id` abonelik ömrü boyunca
sabittir; `transaction_id` ilk satın almada ve **her yenilemede farklıdır**.
İkisini tek alanda birleştirmek ya yenilemeleri unique ihlaliyle reddeder ya
da geçmişi ezer.

`subscription_entitlements` alanları (en az): `user_id`,
`original_transaction_id` (unique), `product_id`, `status`, `expires_at`,
`grace_period_expires_at`, `is_trial`, `auto_renew_status`, `environment`,
`platform`, `last_notification_uuid`, `updated_at`.

### 8b.3 Yetki kaynağı

```sql
-- Tek doğru kaynak: entitlement tablosu. Metadata YOK.
select exists (
  select 1 from public.subscription_entitlements
  where user_id = _user_id
    and (
      expires_at > now()
      or grace_period_expires_at > now()   -- Apple'ın verdiği süre, "tolerans" değil
    )
    and status not in ('refunded', 'revoked')
);
```

Tüm yeni `SECURITY DEFINER` fonksiyonlarında: `set search_path = public`,
açık `REVOKE ALL ... FROM public/anon/authenticated`, yalnız gereken role
`GRANT`. RLS: kullanıcı kendi entitlement'ını **okur**; INSERT/UPDATE yalnız
service_role (`0008_daily_scans.sql` deseni).

### 8b.4 Hesap bağlama — `appAccountToken`

Bir Apple aboneliğinin hangi Rotori hesabına ait olduğu, **istemcinin o anda
gönderdiği `user_id`'ye bırakılamaz.**

Sözleşme: satın alma başlatılırken Supabase kullanıcı UUID'si Apple'a
`appAccountToken` olarak verilir. Sunucu, JWS içindeki `appAccountToken`
değerinin **oturumdaki kullanıcıyla eşleştiğini doğrular**; eşleşmezse
yetki açılmaz. Apple bu alanı yenilemelere de taşır.

Tanımlanması gereken senaryolar: başka Rotori hesabında restore, aynı Apple
hesabı + farklı Supabase hesabı, ilk işlemi başka hesabın sahiplenmesi, hesap
silip yeniden açma, Family Sharing.

### 8b.5 Entitlement durum makinesi

Olay adına göre `switch` yetmez — bildirimler tekrarlanabilir, gecikebilir,
kaçabilir. Kurallar:

| Olay | Etki |
|---|---|
| `SUBSCRIBED`, `DID_RENEW` | `expires_at` ileri alınır, status aktif |
| `DID_FAIL_TO_RENEW` + `GRACE_PERIOD` | Erişim **devam eder**; `grace_period_expires_at` yazılır |
| `DID_FAIL_TO_RENEW` (grace yok) | Erişim sonlandırılabilir |
| `GRACE_PERIOD_EXPIRED` | Erişim kapanır |
| `DID_CHANGE_RENEWAL_STATUS` | **Yalnız otomatik yenilemeyi** değiştirir; mevcut dönemi kapatmaz |
| `DID_CHANGE_RENEWAL_PREF` | Aylık ↔ yıllık geçişi; `product_id` güncellenir |
| `REFUND`, `REVOKE` | **Derhal** kapatır |
| Normal iptal | `expires_at` tarihine kadar erişim sürer |

Ek zorunluluklar:
- `signedPayload` imzası doğrulanır
- `notification_uuid` ile idempotent kayıt
- `environment` + `bundleId` + `appAppleId` + `productId` doğrulanır
- **Eski bildirim yeni durumu ezmez** (sıra dışı teslim korumalı)
- Şüpheli/eksik durumda Apple `Get All Subscription Statuses` çağrılıp
  durum **uzlaştırılır** (reconciliation)
- Production ve sandbox endpoint'leri **ayrı**
- Kaçırılan bildirimler için Notification History kurtarma yolu

### 8b.6 Çevrimdışı yetki modeli

**Seçilen model: cache yalnızca UI kolaylığıdır.** `SharedPreferences` güvenli
bir yetki deposu değildir, o yüzden:

- Ücretli **sunucu** işlemleri (AI rota keşfi, tarama kotası) her zaman
  backend'de `is_premium()` ile korunur — cache'e güvenilmez
- Cache yalnız arayüzün kilitli/açık görünmesini sağlar (uçakta Pro
  kullanıcının kilit ekranı görmemesi için)
- Cache'e son güvenilir **sunucu zamanı** da yazılır; cihaz saati geri
  alınırsa yerel expiry kontrolü kandırılabileceği için karar sunucu
  zamanına göre verilir
- Bu modelde cache'in kırılması bir gelir sızıntısı değildir, çünkü değerli
  yüzeyler sunucuda korunur

### 8b.7 Deneme uygunluğu

"Daha önce denemeyi kullandıysa 7 gün ücretsiz **yazmaz**" kuralının veri
kaynağı **StoreKit 2'nin subscription-group intro eligibility API'sidir**
(`in_app_purchase_storekit` ≥ 0.4.3). Yerel bir `trial_used` anahtarı
yeterli değildir — yeniden kurulumda ve başka cihazda bozulur.

### 8b.8 İstemci satın alma akışı

1. `purchaseStream` dinleyicisi uygulama açılışında **mümkün olan en erken**
   kurulur (arka planda tamamlanan işlemler kaçmasın)
2. İşlem **sunucuda** doğrulanır (`verify-purchase`)
3. Yetki açılır
4. `pendingCompletePurchase` ise **`completePurchase()` çağrılır** — Flutter
   dokümanına göre işlem 3 gün içinde tamamlanmazsa Apple iade edebilir
5. Doğrulama sırasında ağ koparsa işlem **kaybolmaz**: cihazda kalıcı
   "bekleyen doğrulamalar" kuyruğu tutulur, bağlantı gelince tekrar denenir

### 8b.9 Hesap silme ile çakışma

`0004_delete_current_user_rpc.sql` kullanıcıyı tamamen siliyor; Apple
aboneliği ise ayrıca iptal edilmedikçe **devam eder**. Silme akışı:

- Kullanıcıya "hesabı silmek Apple aboneliğini iptal etmez" açıkça söylenir
- Önce "Aboneliği yönet" (sistem sayfası) sunulur
- Silinen kullanıcıya ait sonraki S2S bildirimlerinin nasıl eşleştirileceği
  tanımlanır (orphan işlem kaydı)
- İşlem kaydı finansal/yasal saklama kapsamındaysa kişisel hesaptan
  **ayrıştırılır** → bu yüzden `subscription_entitlements.user_id` için
  doğrudan `cascade delete` dikkatli kullanılır

## 9. Yerel Depolama & Çevrimdışı Destek

- **`shared_preferences`** — dil, tema, kullanıcı istatistiği, plan snapshot.
- **Plan edit snapshot'ı** — lock/capability alanları JSON'da geriye uyumlu
  tutulur. Eski planlar varsayılan olarak düzenlenebilir; generator sabit
  uçuş/varış, otel check-in/out ve satın alınmış biletleri açık kilit
  metadatasıyla üretir.
- **Rota yürütme snapshot'ı** — `DayPlan` içinde opsiyonel schema v1 JSON'dur.
  Eski planlarda bulunmayabilir; aktivite veya zaman çizelgesi değişikliğinde
  otomatik temizlenir. `TripPreferences.planAssumptions` da aynı geriye
  uyumluluk ilkesiyle opsiyoneldir.
- **`flutter_cache_manager`** — OSM harita karoları (iOS/Android). Web'de
  `kIsWeb` kapısı; `NetworkImage`'e düşer.
- **Home widget (iOS)** — App Group üzerinden `UserDefaults`'a yazar; web/Android'de no-op.
- **Bildirim programı** — yerel `timezone` verisi ile `flutter_local_notifications`.
- **Hatırlatıcı erişimi** — var olan hatırlatmalar görülebilir ve
  silinebilir; yeni hazır/özel hatırlatıcı oluşturma UI seviyesinde
  `premiumProvider` ile kapılıdır. Gerçek satın alma entegrasyonunda aynı
  provider sunucu entitlement kaynağına taşınır.

Kural: uçakta çalışmalı. Bir feature yeni bir *zorunlu* ağ bağımlılığı
getirecekse mimari karar `DECISIONS.md`'ye yazılır.

### 9.1 Gözlemlenebilirlik ve analitik

- `TelemetryService`, oturum açmış kullanıcı için `app_open`, yaşam döngüsü,
  güvenli ekran adları ve rota üretim sonuçlarını append-only olarak Supabase'e
  yazar. Ağ yoksa kayıtlar kullanıcıya özel `shared_preferences` outbox'ında
  tutulur; ürün akışı telemetri başarısına bağlı değildir.
- `analytics_events` genel ürün sinyallerini,
  `route_generation_logs` ise aynı `attempt_id` altındaki
  `started/succeeded/failed` fazlarını saklar. İstemci RLS ile yalnız kendi
  satırını ekleyebilir; okuma/güncelleme/silme yetkisi yoktur.
- Rota JSON sözleşmesi tam `Trip.toJson` değildir. Uçuş, otel, bilet, serbest
  not, iletişim alanı, fotoğraf, harita URL'si, gerçek GPS ve beslenme tercihi
  içeriği dışarıda kalır. Hesap silinince bu iki tablo FK cascade ile temizlenir.
- Sentry crash, hata, performans trace'i ve güvenli navigation breadcrumb'ları
  içindir. `sendDefaultPii=false`; e-posta, ekran görüntüsü, UI ağacı ve rota
  JSON'u gönderilmez. DSN yoksa entegrasyon no-op'tur.

## 10. API Katmanı

- Yalnızca **Supabase RPC** ve tablo erişimi (repo katmanı).
- Faz 2 için `apps/api/` altında Express stub (`/api/trips/*`) — canlı değil.
- Mevcut canlı third-party çağrıları: **Open-Meteo** (hava — anahtar yok),
  **OSM tile** (harita — anahtar yok) ve **Sentry** (teknik tanılama).
- İlk sürümde ücretli rota sağlayıcısı çağrılmaz. Günlük planlama tamamen
  cihazdaki offline Japonya rota paketiyle çalışır. Dış navigasyon yalnız
  kullanıcının açık “Haritada aç” eylemiyle Apple/Google Maps'e devredilir.

## 11. Background Jobs

- Şu an server-side job yok. `flutter_local_notifications` uygulama içi zamanlanan
  yerel işleri sürer (bilet açılış hatırlatmaları).

## 12. Test Mimarisi

- **Konum:** `rotori-mobile/test/` — Flutter test paketi.
- **Odak:** domain katmanı (saf Dart) + kritik core sınıfları + kritik viewer
  widget davranışları.
- **Yeni test dosyaları:** `rotori-mobile/test/domain/day_schedule_test.dart`,
  `rotori-mobile/test/domain/place_image_resolver_test.dart`,
  `rotori-mobile/test/core/*`
  (çalışan diff'te). Bunlar F2.0 test regresyonlarını karşılıyor (`70c82d2`).
- **Komut:** `cd rotori-mobile && flutter test`.
- **Plan düzenleme kapsamı:** `plan_schedule_engine_test.dart` komut,
  çakışma, 15 dakikalık slot uygunluğu, çift gün optimizasyonu, sabit aktivite
  ve gün sınırı matrisini;
  `plan_edit_session_test.dart` optimistic update, seri kayıt, rollback ve
  undo'yu; `plan_viewer_test.dart` kilit, pasif slot, uygun-slot-yok,
  erişilebilir drag/drop ve 5 saniyelik undo UI'ını doğrular.
- **Rota optimizasyon kapsamı:** `itinerary_optimizer_test.dart` Tokyo/Osaka
  küme akışı, sabit 14:00 rezervasyonu, ulaşım profilleri, geri dönüş,
  kapanış/minimum süre ve otel dönüşünü; data testleri cache TTL/yönlülük,
  primary/alternate/stale fallback ve AI çağrı/bütçe/cache politikasını;
  `plan_optimization_controller_test.dart` ön izleme/onay ve sonuç cache'ini;
  `plan_viewer_test.dart` görünür aksiyon, güvenli ön koşul ve eski/yeni
  karşılaştırma/onay yüzeyini doğrular. Offline rota paketi ayrıca tüm
  küratörlü şehir/POI yön çiftlerini, zaman bandını ve bilinmeyen şehir
  fallback'ini kapsar. Sonradan uçuş ekleme formu, tek açık kayıt, bilgi
  dialog'u ve açık drawer akordiyonu ayrı widget regresyonlarıyla kapsanır.
  Güncel tam paket **848/848** başarılıdır.
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
- **Site:** `rotori-website/index.html` + `rotori-website/img/` +
  `rotori-website/audio/` birlikte
  versiyonlanır ve statik host'a kopyalanır.
- **Sosyal servis (`rotori-social/`):** tek kaynak `origin`
  (`mennansevim/japan-trip`, monorepo). Pi5 deploy dizini
  `~/rotori-app/rotori-social`; `./deploy.sh` bu dizinden çalışır.
  Geriye uyumluluk için `~/rotori-social` symlink'i aynı dizine işaret eder.

## 15. Bilinen Yumuşak Noktalar

- `apps/api` yalnızca stub — Faz 2 yeniden ele alınacak.
- Google OAuth iOS bundle'da uçtan uca doğrulanmalı (`233a57e` genel akış geldi).
- Home widget yalnızca iOS'ta; Android widget yok.
- Test kapsamı domain'de yüksek, UI'da düşük — bilinçli.
- Plan editleri cihaz içinde seri ve offline-first'tür; sunucuda henüz
  compare-and-swap/revision alanı bulunmadığından aynı planın iki cihazda
  eşzamanlı düzenlenmesi son-yazan davranışına düşebilir.
- Aktivite saatleri gezi yerel saatinin duvar saati dakikaları olarak
  saklanır. Gün sonunu aşan aktivite bölünmez; validasyonla reddedilir.
- Offline rota matrisi canlı sefer, hat kesintisi, peron ve trafik bilemez;
  bunları kesin bilgi gibi göstermez. Paket uygulama sürümüyle güncellenir.
- Optimizasyon ön izleme cache'i ilk sürümde bellek içidir; offline matris
  deterministik ve ucuz olduğu için uygulama yeniden başladığında güvenle
  yeniden üretilebilir.
- Viewer tek günlük ön izleme/onay sözleşmesini görünür biçimde tamamlar.
  Yeni plan oluşturma normal günleri kayıt öncesinde otomatik optimize eder;
  mevcut planların elle yeniden optimizasyonu açık onaylı ön izleme olarak
  kalır. Günler arası
  taşımada mevcut `PlanScheduleEngine` iki günü zamansal olarak yeniden kurar;
  coğrafi rota ön izlemesinin iki günü tek atomik karşılaştırmada göstermesi
  gerçek route gateway/UI işiyle birlikte tamamlanacaktır.

## 16. Rota Optimizasyon v2 Veri Akışı

- `ai_poi_discovery.dart`: kullanıcı onaylı ve cache-miss durumunda, katalog
  yetersiz/eski veya özel ilgi karşılanmıyorsa gezi başına tek AI keşif çağrısı
  politikasını tanımlar. Rota hesabına katılmaz.
- `trip_activity_assignment.dart`: aynı şehirdeki bütün günleri birlikte görür;
  fixed/special-day/erken kapanış/cluster/kapasite alt sınırıyla deterministik
  bucket üretir.
- `itinerary_optimizer.dart`: her bucket içinde yönlü matris üzerinde beam 6
  ve üç local-improvement turu çalıştırır; priority-aware dropping, luggage ve
  kişi/grup maliyetini uygular.
- `route_optimization_validator.dart`: optimizer'dan bağımsız olarak zaman,
  çalışma saati, fixed saat, yönlü leg, dönüş, duplicate/drop muhasebesi ve
  aggregate metrikleri doğrular.
- `plan_optimization_controller.dart`: validator geçmeden preview/persistence
  üretmez.
- Harness schema v2 aynı base senaryoyu dört profile genişletir; generatedAt ve
  elapsed dışındaki semantik çıktı aynı seed'de birebirdir.
- Timeline öğesinin düzenleme/persistence kimliği `id`, katalogdaki mekan
  kimliği ise opsiyonel `placeId` alanıdır. Üretim hattı şehir + `placeId`
  üzerinden kanonik kimlik oluşturur; eski kayıtlarda kontrollü başlık alias'ı
  fallback'tir. Ardışık iki günde aynı kanonik mekanın önerilmesi çıktı
  invariant'ını ihlal eder. Sentetik optimizer harness'ına ek olarak gerçek
  `buildTripFromCities` hattını farklı şehir sıraları, gün uzunlukları ve iki
  dilde çalıştıran üretim QA matrisi bu invariant'ı ve şehir geçişi
  senkronunu ölçer.

## 17. Rota Deneyimi Refactor Sınırı

Rota refactor'u optimizer'ı yeniden yazmaz. `TripActivityAssignmentEngine`,
`BeamSearchItineraryOptimizer` (beam 6), hard constraint'ler ve bağımsız
`RouteOptimizationValidator` karar katmanı olarak korunur.

Yeni sınır optimizer sonucunun kullanıcıya taşınmasıdır:

```text
OptimizationResult.legs
        ↓ saf Dart adapter
RouteExecutionLeg
        ↓
ön izleme / günlük timeline / şehir geçişi / bilet bağlantısı
```

Adapter skor hesaplamaz, sıra veya ulaşım modu seçmez. `RouteLeg` içindeki
süre, yürüyüş, bekleme, aktarma, maliyet, güvenilirlik, tahmin durumu ve
sağlayıcının opsiyonel hat/yön bilgilerini kayıpsız taşır. Kalıcı
`RouteExecutionSnapshot` schema v1 versioned ve opsiyoneldir; eski plan
JSON'ları bozulmaz. Ön izleme ve viewer aynı `RouteExecutionLeg` sunum
sözleşmesini tüketir. Snapshot bulunmayan eski planlarda viewer,
yalnız görünür geçiş bilgisini boş bırakmamak için mevcut sıra üzerinde
koordinat tabanlı tahmini ayaklar türetir. Bu türetim skor hesaplamaz, sırayı
değiştirmez ve kaydedilmez. Yeni planlar ise normal günlerde kayıt öncesi tam
beam-search + validator hattından geçer; mevcut plandaki “Rotayı optimize et”
eylemi aynı motoru açık ön izleme/onay ile yeniden çalıştırır. Ayrıntılı fazlar
ve kalite kapıları:
`docs/ROUTE_EXPERIENCE_REFACTOR_PLAN.md`.

## 18. Premium Çevrimdışı Japonca Metin Çevirisi

Japonca yüzeyindeki `OfflineTranslatorCard`, platform paketlerini doğrudan UI'a
bağlamaz. `OfflineTranslationGateway` metin çevirisini soyutlar. Kart
`premiumProvider` değerini tüketir: ücretsiz kullanıcıda kilitli tanıtım
görünür ve model kontrolü başlamaz; premium aktif olduğunda çeviri alanı aynı
ekranda açılır. Mobil uygulamada ML Kit dil modelleri ilk kullanımda Wi-Fi ile
indirilir; sonraki TR/EN ↔ JA metin çevirileri cihazda çalışır ve metin sunucuya
gönderilmez. Mikrofon, konuşma tanıma ve dinamik sistem sesi kullanılmaz.

Mobil-only çeviri implementasyonu conditional export ile web grafiğinden
ayrılır. Web ön izlemesi premium kilidini gösterir; premium açıkken ML Kit
aksiyonlarını destek-dışı bilgiyle pasif tutar. Çeviri sonuçlarında zorunlu Google Translate atfı
yerel asset olarak gösterilir. Android alt sınırı ML Kit gereği API 23, iOS alt
sınırı mevcut ML Kit hattıyla 15.5'tir.

## 19. Offline Japonya Rota Paketi

Rotori'nin rota sırası kararını veren beam-search ve bağımsız validator aynen
korunur. Değişen katman, bu motora verilen yönlü `RouteMatrix` kaynağıdır.

`OfflineJapanRouteMatrixRepository` her yön için en fazla üç seçenek üretir:

1. **Yürüyüş:** kuş uçuşu mesafeyi şehrin sokak dolaşıklığı katsayısıyla
   düzeltir; yalnız makul yürüme mesafelerinde adaydır.
2. **Toplu taşıma:** şehrin baskın modu, ilk/son yürüyüş, ortalama bekleme,
   araç içi süre, aktarma ve büyük istasyon tamponundan oluşur.
3. **Taksi:** yol dolaşıklığı, şehir içi ortalama hız, zaman bandı ve araç
   başına ücret modeliyle hesaplanır.

Tokyo, Kyoto, Osaka ve Hiroshima için semt/istasyon kümeleri ile zor bağlantı
özel kuralları paketlenir; diğer desteklenen Japonya şehirleri kalibre edilmiş
şehir profiline, bilinmeyen noktalar muhafazakâr genel profile düşer. Sabah ve
akşam yön etkisi deterministik olarak uygulanır. Aynı koordinat 0 dakika,
yakın noktalar yürüyüş, uzak/özel noktalar toplu taşıma ağırlıklı ele alınır.

Matris sürümü paket sürümü + hafta içi/hafta sonu + zaman bandını taşır.
`providerId=rotori-offline-jp`, `isEstimated=true`; `lineId` ve `directionId`
yalnız doğrulanmış paket verisi olmadığı sürece null kalır. Böylece uygulama
tamamen çevrimdışı ve ücretsiz çalışırken tahmini bilgiyi kesin sefer bilgisi
gibi sunmaz.

Konumu doğrulanmayan öğün/özel başlık şehir merkezine zorla bağlanmaz ve rota
düğümü olmaz; timeline'da görünmeye devam eder. İlk planın boşluk doldurma
aşaması kısmen planlanmış bir güne yalnız öğün ekler. Tam/yarım günlük
Disney/USJ/teamLab çapaları ve aynı yerin çift dilli katalog tekrarları dolgu
havuzuna alınmaz. `PlaceSuggestion` ile `CityPlace` kaynakları yalnız görünür
ada göre değil şehir + kanonik katalog kimliğine göre birleştirilir; örneğin
`usj`, `os-usj`, “Universal Studios” ve “Universal Studios Japan” tek mekandır.
Böylece optimizer'a girmeden önce semt bütünlüğü ve günler arası benzersizlik
bozulmaz.

## 20. Saha Gerçekliği Katmanı (Rota v3)

Japonya'ya özgü lojistik, ulaşım ve takvim gerçekleri **optimizer'ın içine
değil, çevresine** eklenir. Motor (`BeamSearchItineraryOptimizer`) yalnız arama
stratejisini yönetir; fizibilite ve maliyet iki ayrı sınıfa çıkarılmıştır.

### 20.1 Sorumluluk ayrımı

| Katman | Sorumluluk | Kural |
| --- | --- | --- |
| `BeamSearchItineraryOptimizer` | Arama stratejisi (beam 6, 3 local-improvement turu) | Kısıt veya skor tanımlamaz |
| `HardConstraintChecker` | **İkili** kapılar → `HardConstraintViolation?` | Skor üretmez |
| `CostFunction` | **Sürekli** maliyet | Fizibiliteyi asla değiştirmez |
| `FieldRealityContext` | Saha bilgisinin tek taşıyıcısı | **Opsiyonel** |

`field == null` iken motor v2 davranışını **birebir** korur. Bu, kalite
kapılarının (0 hard violation, ~%1.77 drop) tek seferde bozulmamasını garanti
eden geriye uyumluluk sözleşmesidir ve harness zarfı karşılaştırmasıyla
doğrulanır.

`_append` akışı **saha düzeltmesi → zamanlama → hard kapılar → maliyet**
sırasındadır. Süre düzeltmesi uygulanmadan kısıt kontrol etmek (ör. Sakura'da
uzayan ziyaret) yanlış "uygulanabilir" verdikti üretir. En pahalı kapı
(sıradaki sabit aktiviteye erişilebilirlik, matris taraması gerektirir) tembel
bir probe olarak en sonda çalışır.

### 20.2 Saf modüller

Hepsi `DateTime.now()` okumaz, ağa çıkmaz, rastgelelik içermez — optimizer
determinizmi buna bağlıdır.

`HardConstraintChecker`, beam içinde aynı ulaşım seçeneği + kalkış anı + yön
birden fazla kez değerlendirildiğinde saf transit-realism sonucunu istek ömrü
boyunca yeniden kullanır. Cache günler veya istekler arasında paylaşılmaz;
böylece saha bağlamı sızmaz ve semantik çıktı değişmeden sıcak yol kısalır.

- **`japan_calendar.dart`** — Resmî tatil takvimi (sabit tarihler, Happy Monday
  sistemi, 1980–2099 için equinox yaklaşımı, 振替休日 zinciri, 国民の休日),
  `ClosureResolver` (teishukubi + **Holiday Shift**: kapanış günü resmî tatilse
  mekan açılır ve kapanış tatil olmayan ilk güne kayar; Golden Week zinciri
  kapanışı birden fazla gün iter), `JapanCrowdModel` (şehir bazlı sakura/kōyō
  pencereleri, Golden Week, Obon, yılbaşı).
- **`japan_transit_realism.dart`** — `RailPassType`, `ShinkansenService`,
  `StationComplexity` (labyrinth → +15 dk `stationNavigationBuffer`, kalkış ve
  varış ayrı ayrı sayılır), `TrafficRiskPolicy` (peak 1.30 / off-peak 1.10,
  yalnız `bus`/`taxi`).
- **`luggage_logistics.dart`** — `LuggageHandlingStrategy` karar ağacı ve otel
  check-in penceresi. Erken varışta coin locker ile otele erken bırakma **dakika
  bazında yarışır**; sabit kural yerine karşılaştırma kullanılır.
- **`place_identity_resolver.dart`** — Kana→Hepburn romaji tablosu (digraph,
  促音, ん+b/m/p→m), kapalı kanji okuma sözlüğü, macron/Türkçe katlama,
  Levenshtein, `CanonicalPlaceHash` (32-bit FNV-1a). ASCII girdide çıktı v2 ile
  birebir aynıdır.
- **`route_field_context.dart`** — `RepeatPolicy` değerlendiricisi +
  `FieldRealityContext` toplayıcısı (kategori başına sezon çarpanı önbellekli).
- **`minute_math.dart`** — Çarpan zincirinde (`100 * 1.10` → 110.00000000000001)
  tek dakikalık kaymayı engelleyen ortak yukarı-yuvarlama sözleşmesi.

### 20.3 Bagajın nereye gittiği

Şehir geçişi olan günde istasyon çıkışı **doğrudan aktiviteye bağlanamaz**.

| Strateji | Varış tamponu | Gün sonu | Not |
| --- | --- | --- | --- |
| `yamatoForward` | **0** | 0 | Bagaj ertesi gün varır; tampon **bypass** |
| `coinLocker` | +20 dk | +10 dk | Büyük valizde doluluk uyarısı |
| `hotelEarlyDrop` | 2×sapma + resepsiyon | 0 | Check-in öncesi |
| `hotelCheckIn` | sapma + resepsiyon | 0 | Pencere açık |

Yamato kapıları: bagaj boyutu uygun **ve** mesafe ≥120 dk **ve** varışta ≥2 gece
**ve** kaynak otelden çıkış ≤10:00 (aynı gün kargo son teslim). Herhangi biri
düşerse strateji erken-varış ağacına iner. Tampon yalnız günün **ilk**
yerleşimine, gün sonu alma süresi ise **dönüş bacağına** eklenir.

Otel `checkInEndTime` (varsayılan 22:00) sonrası varış **hard ihlaldir** —
tampon değil, plan geçersizliğidir.

### 20.4 Intent-aware tekrar kısıtı

`hard-zero` tek kural değildir:

- `hardZero` (varsayılan) — ardışık iki güne aynı kanonik mekan konmaz.
- `repeatableZone` — bölge (Akihabara, Shibuya) ve tematik park (USJ, Disney)
  ardışık 2 güne atanabilir.
- `timeQuota` — büyük müze ilk gün kotasını doldurmadıysa kalan süre için tekrar
  önerilir (`remainingQuotaMinutes`).
- `userOverride` — kullanıcı açıkça seçtiyse tüm deduplication ezilir.

**Bölge adları kasten alias almaz.** "Arashiyama Bambu" ile "Arashiyama Maymun
Parkı" tek anahtara indirilirse yanlışlıkla aynı mekan sayılır; bölge tekrarı
alias değil `RepeatPolicy` işidir.

### 20.5 Geçiş satırı tek kaynaktır

`CityTransitionPlan.mode` timeline satırının, gün başlığının ve rozetin tek
doğruluk kaynağıdır. v3'te seçenek listesi (`options`) **motor** tarafından
üretilir; UI yalnız gösterir ve seçer. Böylece "üst rozet Otobüs ama timeline
JR Special Rapid" sınıfı projeksiyon kayması yapısal olarak imkânsızdır.
JR Pass ile seçilemeyen servis listede `isBlockedByPass` ile **görünür** kalır —
"pass'im var, Nozomi neden yok?" sorusu sessiz bırakılmaz.

### 20.6 JSON v3 sözleşmesi

Şema: `docs/schemas/rotori-plan-v3.schema.json`.

Saha meta verisi opsiyonel iç nesnelere taşınır: `TimelineItem.transit` /
`.repeat` / `.closure` / `.canonicalPlaceHash`, `DayPlan.luggage` / `.crowd`,
`CityTransitionPlan.railPass` / `.options`. Tüm alanlar varsayılan değerdeyken
**serileştirilmez**; v2 dokümanı v3 okuyucuda kayıpsız açılır (round-trip
regresyona bağlı) ve v2'nin düz `repeatAllowed` bayrağı `userOverride`
politikasına yükseltilir.
