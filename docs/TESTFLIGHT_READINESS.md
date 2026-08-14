# Rotori TestFlight Hazırlığı

Son güncelleme: **2026-08-14**

Bu dosya TestFlight hazırlığının tek takip listesidir. Yeni oturumlarda önce
`docs/CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CURRENT_TASK.md` ve
`docs/DECISIONS.md` zorunlu sırayla okunur; ardından çalışmaya bu dosyadaki ilk
işaretlenmemiş P0 maddeden devam edilir.

## Doğrulanmış mevcut durum

- [x] Flutter analyze temiz.
- [x] Tam Flutter test paketi başarılı.
- [x] Auth, harita ve Premium hedefli testleri 40/40 başarılı.
- [x] Temiz `flutter build ios --release --no-codesign --no-pub` başarılı.
- [x] İmzasız `Runner.app` 132,7 MB üretildi.
- [x] Production auth ekranındaki gömülü demo hesabı kaldırıldı.
- [x] `PrivacyInfo.xcprivacy` Runner resource paketine bağlandı ve build içinde
      doğrulandı.
- [x] TR/EN `InfoPlist.strings` izin açıklamaları build içinde doğrulandı.
- [x] `Runner.entitlements` bütün Runner build ayarlarına bağlandı.
- [x] Xcode target capability kaydında Sign in with Apple açık.
- [x] Google/CARTO raster endpoint'leri kaldırıldı; uygulama içi haritalar
      standart OSM tile katmanını kullanıyor.
- [x] Harita toplu ön-indirmesi, kalıcı disk cache ve
      `flutter_cache_manager` bağımlılığı kaldırıldı.
- [x] Premium butonu ve mevcut Pro bilgilendirme akışı korundu.

## P0 — İlk dahili TestFlight yüklemesi

### 1. Apple imzalama

- [ ] Aktif Apple Developer Program üyeliğini doğrula.
- [ ] Xcode'a doğru Apple hesabını bağla.
- [ ] Runner için Automatic Signing'i doğrula.
- [ ] App ID'nin `com.mennansevim.rotori` olduğunu doğrula.
- [ ] Geçerli Apple Distribution sertifikası oluştur/yükle.
- [ ] Sign in with Apple capability içeren App Store provisioning profile
      oluştur veya otomatik olarak yenilet.
- [ ] App Store Connect'te Rotori uygulama kaydını oluştur/doğrula.

**Tamamlanma kanıtı:** Xcode Signing & Capabilities ekran görüntüsü ve hatasız
imzalı Archive.

### 2. Apple ve Supabase giriş ayarları

- [ ] Apple Developer App ID üzerinde Sign in with Apple capability açık mı
      kontrol et.
- [ ] Gerekliyse Services ID, Sign in with Apple key ve private key oluştur.
- [ ] Supabase Apple provider ayarlarını doğrula.
- [ ] Apple callback/redirect adreslerini Supabase ayarlarıyla eşleştir.
- [ ] Google OAuth production callback ayarlarını doğrula.
- [ ] Email confirmation'ı production için aç.
- [ ] Kayıt, email onayı, parola sıfırlama ve tekrar giriş akışlarını dene.

**Tamamlanma kanıtı:** Gerçek cihazda Apple login success/cancel/error/revoke,
Google login ve email confirmation sonuçları.

### 3. Production Supabase ve Sentry

- [ ] `0009_analytics_observability.sql` migration'ının production Supabase'e
      uygulandığını doğrula.
- [ ] Release değerlerini `--dart-define` veya güvenli Xcode/CI config üzerinden
      sağla.
- [ ] `SENTRY_DSN` ve `SENTRY_ENVIRONMENT=production` ile release build al.
- [ ] Kontrollü test hatasının doğru release/environment ile Sentry'de
      göründüğünü doğrula.
- [ ] Rota üretiminde `started` ve `succeeded` analytics satırlarını doğrula.
- [ ] Analytics payload'ında uçuş, otel, bilet, not, email veya GPS olmadığını
      kontrol et.
- [ ] Paketlenen `.env` içinde service-role/private key bulunmadığını doğrula.
- [ ] Release build config hazır olduktan sonra `.env` asset fallback'ini
      production paketinden çıkar.

### 4. Gerçek cihaz release kapısı

- [ ] Mevcut iOS cihazıyla uyumlu Xcode/device support sorununu çöz.
- [ ] İmzalı release build'i gerçek iPhone'a kur.
- [ ] Cold launch; crash, blank screen ve backend config kontrolü.
- [ ] Login/logout ve korumalı route kontrolü.
- [ ] Plan oluştur, kaydet, kapat, yeniden aç; veri kaybı olmadığını doğrula.
- [ ] Hesap silme ve temiz local state kontrolü.
- [ ] Location allow/deny/settings dönüşü.
- [ ] Camera ve Photos allow/deny/settings dönüşü.
- [ ] Bildirim allow/deny, schedule ve gerçek teslim kontrolü.
- [ ] OCR, canlı fiyat tarayıcı ve cihaz üstü çeviri kontrolü.
- [ ] Uçak modu ve zayıf ağ senaryosu.
- [ ] Küçük iPhone, güncel iPhone ve iPad smoke testi.

**Tamamlanma kanıtı:** Cihaz/OS/build numarası, PASS/FAIL listesi ve kritik
akışların kısa ekran kayıtları.

### 5. App Store Connect ve yükleme

- [ ] Marketing version ve benzersiz build number belirle; her tekrar yüklemede
      build number'ı artır.
- [ ] Privacy Policy URL ve Support URL gir.
- [ ] App Privacy cevaplarını uygulamadaki Email, Other User Content, User ID,
      Product Interaction, Crash Data ve Performance Data kullanımıyla eşleştir.
- [ ] Export compliance sorusunu mevcut standart HTTPS/TLS kullanımına göre
      yanıtla; `ITSAppUsesNonExemptEncryption=false` değerini tekrar doğrula.
- [ ] Beta App Description, Feedback Email ve What to Test metinlerini hazırla.
- [ ] İnceleme hesabını yalnız App Store Connect Review Notes alanına ekle.
- [ ] İmzalı archive oluştur, Organizer validation çalıştır ve yükle.
- [ ] App Store Connect'te işlenmiş build'in hata/uyarılarını kontrol et.
- [ ] Önce küçük bir internal tester grubuna dağıt.

## P1 — Harici TestFlight öncesi

### Premium

- [ ] Karar ver: harici beta yalnız bilgilendirme/paywall ile mi çıkacak, yoksa
      StoreKit satın alma sistemi tamamlanacak mı?
- [ ] Premium butonunun şu anda satın alma yapmadığını Beta Review Notes'ta açık
      belirt veya harici beta öncesinde gerçek satın alma akışına bağla.
- [ ] StoreKit yapılacaksa purchase, restore, server-side JWS doğrulaması,
      entitlement ve App Store Server Notifications V2'yi tamamla.
- [ ] `debug_premium` ve kullanıcı tarafından yazılabilen
      `raw_user_meta_data.premium` kaynaklarını production entitlement kaynağı
      olmaktan çıkar.

### Harita

- [ ] Standart OSM endpoint'ini yalnız düşük hacimli TestFlight geçiş çözümü
      olarak tut.
- [ ] Genel App Store yayını öncesinde ticari kullanım/SLA sağlayan harita
      sağlayıcısını seç.
- [ ] Offline harita tekrar istenecekse yalnız ön-indirme ve offline paket
      lisansı veren sağlayıcıyla uygula.
- [ ] Yeni sağlayıcının attribution, cache ve kullanım şartlarını doğrula.

### Yasal ve içerik

- [ ] TR/EN Kullanım Koşulları sayfalarını yayınla.
- [ ] Destek sayfalarındaki “abonelik/IAP yok” metnini gerçek Premium kapsamıyla
      eşleştir.
- [ ] Wikimedia/Unsplash görselleri için kaynak, yazar ve lisans atıflarını
      doğrula veya görselleri sahip olunan içeriklerle değiştir.
- [ ] App Store yaş derecelendirmesi, kategori, telif ve içerik hakları
      cevaplarını hazırla.

### Ürün kapsamı

- [ ] Widget ilk sürümde olacaksa native Widget Extension ve App Group'u
      tamamla; olmayacaksa mağaza metinlerinde widget vaadi verme.
- [ ] iPad desteği korunacaksa kritik ekranların tamamını iPad'de doğrula;
      değilse ilk upload öncesinde device family kapsamını değiştir.
- [ ] Branded launch screen ve son görsel cila kararını ver.

## Devam sırası

1. Apple imzalama ve App Store Connect kaydı.
2. Apple/Supabase authentication ayarları.
3. Production Sentry/analytics doğrulaması.
4. Gerçek cihaz release QA.
5. İmzalı Archive ve internal TestFlight yüklemesi.
6. Premium, harita sağlayıcısı ve yasal içerik tamamlandıktan sonra harici beta.

## Kalan bilinen teknik uyarılar

- Bazı Flutter eklentileri henüz iOS Swift Package Manager desteği sunmuyor;
  mevcut physical-device release build başarılı, ancak gelecekteki Flutter
  sürümleri için paket güncellemeleri takip edilmeli.
- Mevcut Pod yapılandırması Apple Silicon iOS 26+ simülatöründe bazı
  dependency'lerin arm64 desteğini dışlıyor. Fiziksel cihaz build'ini
  engellemiyor; simulator QA kapsamını daraltıyor.
- İmzasız build hazır olsa da bu makinede geçerli dağıtım sertifikası ve App
  Store provisioning profile olmadan TestFlight'a yükleme yapılamaz.
