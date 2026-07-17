# Sign in with Apple — Kurulum Notları

Bu belge, "Apple ile Giriş Yap" özelliğinin **kod tarafı hazır** olduğunu ve
üretimde çalışması için gereken **manuel Xcode + Supabase adımlarını** listeler.
Bu adımlar Xcode ve Apple Developer/Supabase panelleri gerektirdiğinden burada
otomatik yapılamaz; aşağıdaki adımları bir kez uygulayın.

> Kod durumu: `lib/features/auth/auth_repository.dart` (`signInWithApple()`) ve
> `lib/features/auth/auth_screen.dart` (platform gate'li buton) hazır.
> `ios/Runner/Runner.entitlements` dosyası oluşturuldu ancak **Xcode
> projesine (project.pbxproj) bilinçli olarak eklenmedi** — riskli otomatik
> düzenlemeden kaçınmak için bunu Xcode üzerinden yapın (Adım 2).

---

## 1. Xcode — "Sign in with Apple" capability'sini etkinleştir

1. `ios/Runner.xcworkspace` dosyasını Xcode ile aç.
2. Sol panelde **Runner** hedefini seç → **Signing & Capabilities** sekmesi.
3. Geçerli bir **Team** seçili olduğundan emin ol (Apple Developer üyeliği şart).
4. **+ Capability** → **Sign in with Apple** ekle.
   - Bu işlem, Xcode'un `Runner.entitlements` dosyasını proje ayarlarına
     (`CODE_SIGN_ENTITLEMENTS`) otomatik bağlamasını sağlar.

## 2. Entitlement dosyasını doğrula / bağla

- Repoda hazır dosya: `ios/Runner/Runner.entitlements`
  ```xml
  <key>com.apple.developer.applesignin</key>
  <array><string>Default</string></array>
  ```
- Adım 1 capability'yi eklerken Xcode zaten aynı anahtarı yazar. Eğer Xcode
  ayrı bir entitlements dosyası oluşturursa, iki dosyayı tek dosyada birleştir
  ve **Build Settings → Code Signing Entitlements** değerinin
  `Runner/Runner.entitlements` olduğundan emin ol.

## 3. Apple Developer portalı

1. https://developer.apple.com → **Certificates, Identifiers & Profiles**.
2. **Identifiers** → App ID'ni (bundle id: `Info.plist`'teki değer) seç →
   **Sign in with Apple** capability'sini işaretle.
3. **Services ID** oluştur (Supabase için gerekir; web/redirect akışı):
   - Identifiers → **+** → **Services IDs** → tanımla (örn. `app.japantrip.signin`).
   - "Sign in with Apple" → **Configure** → Primary App ID'yi ve
     **Return URLs** olarak Supabase callback'ini ekle (Adım 4'teki URL).
4. **Key** oluştur: Keys → **+** → "Sign in with Apple" işaretle → indir
   (`AuthKey_XXXX.p8`). **Key ID** ve **Team ID**'yi not al.

## 4. Supabase Auth paneli

1. Supabase Dashboard → **Authentication → Providers → Apple** → **Enable**.
2. Doldur:
   - **Services ID (Client ID):** Adım 3.3'teki Services ID.
   - **Team ID:** Apple Developer Team ID.
   - **Key ID:** Adım 3.4'teki Key ID.
   - **Private Key:** `.p8` dosyasının içeriği.
3. **Redirect / Callback URL** (Apple Return URL olarak da girilir):
   ```
   https://<PROJE-REF>.supabase.co/auth/v1/callback
   ```
4. Kaydet.

> Native iOS akışında (bu uygulamanın kullandığı `signInWithIdToken`) Apple
> `identityToken` doğrudan cihazdan alınır; Services ID + key yapılandırması
> Supabase'in token'ı doğrulaması için yine de gereklidir.

## 5. Nonce / güvenlik akışı (kodda uygulanmış — referans)

- Uygulama güvenli **ham (raw)** nonce üretir (`generateRawNonce`).
- Apple'a bunun **SHA-256 hex özeti** gönderilir
  (`getAppleIDCredential(nonce: hashedNonce)`).
- Supabase'e **ham nonce** + `identityToken` gönderilir
  (`signInWithIdToken(provider: apple, idToken:, nonce: rawNonce)`).
- Bu, replay saldırılarına karşı standart Supabase + Apple desenidir.

## 6. Test

- Gerçek akış yalnızca **fiziksel/simülatör iOS veya macOS** cihazında ve
  yukarıdaki yapılandırma tamamlandıktan sonra çalışır.
- Web ve Android derlemelerinde buton **hiç render edilmez** (platform gate:
  `!kIsWeb && (iOS || macOS)`), bu yüzden bu platformlarda ek yapılandırma
  gerekmez.
