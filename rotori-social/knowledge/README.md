# knowledge/ — Insider Veri Bankası

Bu klasör, LLM'in Reels metinlerini üretirken kullandığı **gerçek deneyim
kaynağıdır**. Buradaki her satır, üretilen `hook`, `aciklama` ve `overlays`
için hammadde olarak sayılır.

## Dosyalar

- [japonya_tuyolar.md](japonya_tuyolar.md) — ana bilgi bankası (numaralanmış
  bölümler, aile-14-gün özelinde). Kullanıcı doldurur.

## Nasıl kullanılır

1. `japonya_tuyolar.md`'yi aç
2. Aklına gelen tüyoyu ilgili bölüm altına tek cümlelik madde olarak ekle
3. Rakam/saat/fiyat varsa yaz, tag ekle (`#tokyo #ulasim` vb.)
4. Şüpheli bilgi YAZMA — LLM sadece buraya yazılana güvenecek

## Yazım stili örnekleri

**İYİ ✓**
```
- Namba'daki 7-Eleven'da bavul dolabı var, 700 yen, app rezervasyon zorunlu #osaka #ulasim
- NOZOMI Shinkansen'de sağ pencere = Fuji Dağı manzarası, Tokyo → Osaka yönünde #shinkansen #tokyo
- IC Card'ı fastfood'da menüde kullanamıyorsun, kasada sadece #odeme #genel
```

**KÖTÜ ✗** — jenerik, doğrulanamaz, boş
```
- Japonya çok güzeldi
- Metro sistemi iyi
- Erken kalkın
```

## LLM entegrasyonu

Bu dosya değişince, bir sonraki `.venv/bin/python -m src.step3_dify` çağrısı
otomatik yeni içerikle Dify workflow'una context olarak yollanır (entegrasyon
kod tarafında eklendiğinde). Manuel adım gerekmez.
