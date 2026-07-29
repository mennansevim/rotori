# CURRENT_TASK.md — Bugünün İşi

> Bu dosya *bugünkü* çalışmanın canlı görünümüdür. Her tamamlanan görevden
> hemen sonra güncellenir.

**Bugünün tarihi:** 2026-07-29
**Aktif branch:** `main`
**Sprint hedefi:** F2 — Rebrand (Tabi → Rotori) sonrası viewer/planner cilası +
  App Store gönderim öncesi son regresyonlar.

---

## Aktif Hedef

`main` üstünde 17 dosyalık büyük bir *commit-edilmemiş* refaktor duruyor
(≈ +1685 / −921 satır, `git diff --stat`). Ana yük:

- `plan_viewer_screen.dart` **+1615 satır** — viewer'ın plan görüntüleyicisi
  büyük bir yeniden yazımdan geçmiş (satır içi düzenleme + top-down shinkansen
  planı gibi son commit'lerin devamı).
- `welcome_step.dart` **-464 satır** — welcome adımı sadeleştirildi (muhtemelen
  içerik `day_schedule.dart` / `place_image_resolver.dart` gibi yeni domain
  dosyalarına dağıtıldı).
- Yeni domain dosyaları: `mobile/lib/domain/day_schedule.dart`,
  `mobile/lib/domain/place_image_resolver.dart`.
- Yeni test dosyaları: `mobile/test/domain/day_schedule_test.dart`,
  `mobile/test/domain/place_image_resolver_test.dart`, `mobile/test/core/*`.
- `website/index.html` yenilenmiş (+132/-132 net) — Design System v2
  cilalaması (`4578280` sonrası ince ayar).

## Tamamlananlar (bu ve önceki oturumlardan)

- ✅ **2026-07-22** Marka ismi Rotori olarak rebrand + sitede/uygulamada
  tutarlı hale getirildi (`360e5ae`).
- ✅ **2026-07-22** Website F1 seti (privacy + support + footer link + copy
  tazeleme) — `08d7449`, `cbd592a`.
- ✅ **2026-07-22** F1 App Store hazırlığı: Info.plist, hesap silme, aydınlık
  mor tanıtım (`11f3541`).
- ✅ **2026-07-2x** Design System v2 devreye alındı (`4578280`).
- ✅ F2.0 test regresyonları çözüldü — `plan_viewer` + `day_map` (`70c82d2`).
- ✅ Daha önce: Supabase auth uçtan uca (`233a57e` · Google OAuth),
  QA framework 100 senaryo (`13969b9`, `888feb2`), viewer satır içi düzenleme
  (`e66429c`), top-down shinkansen planı (`c7ef17f`).

## Kalanlar (kısa vadeli)

- [ ] **Commit disiplini:** 17-dosyalık diff'i mantıksal parçalara böl:
  1. Yeni domain + testleri (`day_schedule` + `place_image_resolver`).
  2. `plan_viewer_screen.dart` yeniden yazımı + ilgili viewer değişiklikleri.
  3. `welcome_step.dart` sadeleştirmesi + planner değişiklikleri.
  4. `l10n.dart` yeni anahtarlar.
  5. `website/index.html` ince ayar.
- [ ] `flutter analyze` ve `flutter test` yeşile boyanmalı — commit
  öncesi mutlaka çalıştır.
- [ ] `place_coords.dart` +32 satır ve `city_places.dart` -1 satır — yeni
  yerlerin koordinatları eklenmiş mi doğrula.
- [ ] Yeni `img/` ve `website/img/hand-mobile.svg` untracked — ne oldukları
  netleşince ya commit'le ya `.gitignore`'a al.
- [ ] Supabase Auth "Confirm email" prod öncesi **aç** (hâlâ kapalı — `[[supabase-backend]]`).
- [ ] App Store submission checklist — Sign in with Apple Services ID
  yapılandırması ($99/yıl Developer + Services ID) — `[[supabase-backend]]`.

## Bilinen Blocker'lar

- **2026-07-29 regresyon kontrolü:** `flutter test` sonucunda 327 test geçti,
  10 widget testi başarısız oldu. Hatalar ağırlıkla sadeleştirilen welcome
  akışının eski metinlerini ve viewer'ın eski menü/tema davranışını bekleyen
  testlerde. Push sonrasında testleri güncel ürün davranışıyla hizalama öncelikli.
- `flutter analyze` uygulama hatası üretmedi; 1 deprecated API bildirimi ve
  testlerde 4 lint bilgisi nedeniyle komut 5 issue ile kapandı.

## Sıradaki Uygulama Adımı

1. Başarısız 10 widget testini güncel welcome/viewer davranışıyla hizala.
2. `flutter analyze` bildirimlerini temizle ve `flutter test`i yeşile boya.
3. Yeni domain dosyalarını + testlerini ayrı bir commit'te sabitle
   (küçük, geri alınabilir).
4. Sonra `plan_viewer_screen.dart` yeniden yazımını tek commit'te at.
5. En son planner sadeleştirmesi + l10n anahtar farkını commit'le.
6. Website ince ayarı ayrı commit (yalnızca `website/index.html`).

## Şu An Değişen Dosyalar

```
mobile/lib/core/l10n.dart
mobile/lib/core/router.dart
mobile/lib/domain/city_places.dart
mobile/lib/domain/day_schedule.dart          (yeni)
mobile/lib/domain/fill_empty_days.dart
mobile/lib/domain/itinerary_generator.dart
mobile/lib/domain/place_coords.dart
mobile/lib/domain/place_image_resolver.dart  (yeni)
mobile/lib/features/planner/planner_screen.dart
mobile/lib/features/planner/steps/journey_step.dart
mobile/lib/features/planner/steps/welcome_step.dart
mobile/lib/features/plans/plan_viewer_screen.dart
mobile/lib/features/plans/plans_list_screen.dart
mobile/lib/features/shared/place_detail_sheet.dart
mobile/lib/features/viewer/day_map_screen.dart
mobile/lib/features/viewer/offline_tile_provider.dart
mobile/test/core/                            (yeni klasör)
mobile/test/domain/day_schedule_test.dart    (yeni)
mobile/test/domain/fill_empty_days_test.dart
mobile/test/domain/place_coords_test.dart
mobile/test/domain/place_image_resolver_test.dart (yeni)
website/index.html
img/                                          (untracked — kaynağını netleştir)
website/img/hand-mobile.svg                   (untracked — commit adayı)
```

## Son Commit'ler (referans)

```
4578280 feat(website): baştan aşağı revizyon — Design System v2
70c82d2 fix(test): plan_viewer + day_map regresyonlarını çöz — F2.0
cbd592a copy(website): 'Hesap gerekmez' → 'Ücretsiz · reklamsız'
08d7449 feat(website): Privacy Policy + Destek sayfaları + footer link
11f3541 feat(release+web): F1 App Store prep — Info.plist, hesap silme
```
