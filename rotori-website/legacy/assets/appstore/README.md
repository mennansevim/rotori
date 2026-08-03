# App Store creative assets — Rotori

## İçerik

6 PNG (1290×2796 — iPhone 6.7" Pro Max), Apple Design Award tarzı cinematic mockuplar:

| # | Dosya | Konu | Örnek başlık |
|---|-------|------|--------------|
| 01 | `01-hero.png` | Hero | Sürpriz yok. Plan var. |
| 02 | `02-plan.png` | Plan adımı | Şehirleri seç. Günleri biz paylaştıralım. |
| 03 | `03-discover.png` | GPS keşif | Yürü. Keşfet. Kazan. |
| 04 | `04-meet.png` | Sohbet | Yabancı yok. Ekip var. |
| 05 | `05-offline.png` | Uçak modu | Uçak modunda bile yanında. |
| 06 | `06-endcard.png` | Marka kapanışı | Rotori · Sürpriz yok, plan var. |

## App Store yükleme

**App Store Connect → My Apps → Rotori → App Store → 6.7" Display →** ilk 5 PNG'yi sürükle-bırak.

- **Zorunlu**: iPhone 6.7" Pro Max screenshot'ları (1290×2796)
- **Opsiyonel**: 6.5" (1284×2778) — Apple otomatik downscale eder, 6.7" tek başına yeterli
- **App Preview video**: `website/appstore-preview.html`'i tam ekran açıp QuickTime ile screen record → 30 sn'ye kadar trim

## Yeniden üretim

Kaynak SVG'ler `website/appstore-preview.html` içinde (5 sahne + endcard). İçerik/renk değişikliği yapıp PNG'leri yenilemek için:

```bash
cd assets/appstore
node build.mjs
```

Chrome headless ile 6 PNG'yi 1290×2796'da üretir. `build/` klasörü intermediate HTML dosyalarını içerir (versiyon kontrolünde yer almaz).

## Diğer boyutlar

Başka cihaz aileleri için:
- **iPhone 6.5"**: 1284×2778 — `W=1284, H=2778` build.mjs'te değiştir
- **iPad 12.9"**: 2048×2732 — İçerik yeniden tasarlanabilir (mobile-first mockuplar geniş ekrana uymayabilir)

## Font notu

SVG'lerde `Anthropic Sans` referansı var — Chrome bulamayınca fallback olarak system-ui / SF Pro Text kullanır. Sistemde `SF Pro Text` yüklü olduğu için Apple ürünlerindeki tipografik hisse yakın çıktı verir.
