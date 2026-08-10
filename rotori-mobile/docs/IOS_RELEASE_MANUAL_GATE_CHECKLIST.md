# iOS Release Manual Quality Gate Checklist

Bu checklist, `mobile/docs/RELEASE_QA_ANALYSIS_2026-07-26.md` bulgularına göre iOS release öncesi manuel kapı (gate) olarak kullanılır.

> Son cihaz denemesi (11 Ağustos 2026): iPhone 14 / iOS 27 eşleşti, debug build
> ve imzalama tamamlandı; Xcode 26.6 developer disk image'ı cihaza bağlayamadığı
> için yükleme yapılamadı. Bu altyapı engeli çözülmeden aşağıdaki gerçek-cihaz
> maddeleri PASS sayılmaz.

## P0 — Release Blocker

- [ ] **Release build smoke**: Uygulama gerçek cihazda açılıyor; crash/blank screen yok.
- [ ] **Auth route güvenliği**: Login olmadan protected ekranlara erişim yok; logout sonrası geri dönüş engelli.
- [ ] **Apple Sign-In capability**:
  - [ ] `Runner.entitlements` içinde `com.apple.developer.applesignin = Default` var.
  - [ ] Xcode Signing & Capabilities altında **Sign in with Apple** açık.
  - [ ] Apple Developer / Supabase credential eşleşmesi doğrulandı.
- [ ] **Plan veri bütünlüğü**: Plan kaydet/aç sonrası veri kaybı yok.
- [ ] **Permission açıklamaları**: `Info.plist` usage description metinleri doğru ve anlamlı.
- [ ] **Cepte Çevirmen gizlilik kapısı**:
  - [ ] Ücretsiz kullanıcıda çevirmen kilitli; dil modeli kontrolü/indirmesi başlamıyor.
  - [ ] Premium aktif olduğunda çevirmen aynı ekranda açılıyor.
  - [ ] İlk çevrimiçi kullanımda TR/EN + JA çeviri modelleri indiriliyor ve Google atfı görünür.
  - [ ] Uçak modunda Türkçe → Japonca ve Japonca → Türkçe metin çevirisi çalışıyor.
  - [ ] Ağ incelemesinde çevrilecek metin ve sonuç için giden istek yok.
  - [ ] Mikrofon/konuşma izni istenmiyor; App Store Connect beyanı mevcut uygulamayla eşleşiyor.

## P1 — Önemli (yüksek öncelik)

- [ ] **Widget scope aktifse**: App Group (`group.com.mennansevim.rotori`) Runner + Widget target’ta bağlı.
- [ ] **Bildirimler**: İzin verildiğinde schedule + teslim çalışıyor; deny halinde fallback doğru.
- [ ] **Location / Camera / Photos deny akışları**: Çökme yok, kullanıcı yönlendirmesi net.
- [ ] **Offline/zayıf ağ**: Ana akışlarda sonsuz loading yok, hata görünümü anlaşılır.
- [ ] **iPad kullanım testi**: Kritik ekranlarda taşma/interaction sorunu yok.

## Apple Sign-In Test Matrisi

| Senaryo | Beklenen | Seviye | Kanıt |
|---|---|---|---|
| Başarılı giriş | Session açılır, `/plans` görünür | P0 | Video + log |
| Cancel | App çökmez, auth ekranında kalır | P1 | Video |
| Error (network vb.) | Anlaşılır hata + retry | P0 | Video + hata kodu |
| Revoke (Apple ID settings) | Eski session geçersiz, tekrar auth ister | P0 | Video |
| Logout | Protected route erişimi kapanır | P0 | Video |
| Account deletion | Politika uyumlu silme + temiz state | P0 | API/UI kanıt |

## Permissions Matrisi

| Permission | Allow beklenen | Deny beklenen | Settings sonrası |
|---|---|---|---|
| Location | Konumlu özellikler çalışır | Çökmeden fallback | Deny→Allow sonrası toparlar |
| Camera | OCR kamera akışı çalışır | İzin mesajı + fallback | Sonradan allow ile çalışır |
| Photos | Galeriden seçim + OCR çalışır | Çökmeden fallback | Sonradan allow ile çalışır |
| Notifications | Reminder schedule + teslim | Düzgün bilgilendirme | Sonradan allow ile yeni reminder çalışır |

## Real Device Matrix (minimum)

- [ ] iPhone küçük ekran (örn. iPhone SE/mini, iOS 17.x)
- [ ] iPhone modern cihaz (örn. iPhone 15/16, iOS 18.x)
- [ ] iPad (iPadOS 17.x+)

Her cihazda minimum:
- [ ] Cold launch
- [ ] Login/logout
- [ ] Apple Sign-In (success + cancel)
- [ ] Reminders + notification permission
- [ ] Camera/Photos permission akışları
- [ ] (Scope’taysa) Widget ekleme/güncelleme

## Sign-off

- Release Version:
- Build Number:
- QA Owner:
- Eng Owner:
- Product Owner:

### Sonuç
- Overall: [ ] PASS  [ ] FAIL
- P0: [ ] PASS  [ ] FAIL
- P1: [ ] PASS  [ ] FAIL

### Kanıtlar
- Test run linki:
- Video/Screenshot klasörü:
- Crash log / analytics linki:
- Known issues / waiver:

### Onay
- QA Owner / Tarih / İmza:
- Eng Owner / Tarih / İmza:
- Product Owner / Tarih / İmza:
