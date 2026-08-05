# Tasarım Spesifikasyonu

## Ürün fikri

Japonya Rüyası, Instagram için içerik fikri üretme, görsel/caption hazırlama,
onaylama, planlama, yayınlama ve performans analizi işlerini tek yerde toplar.
Arayüz bir yönetim panelinden çok çağdaş bir Japon seyahat dergisi hissi
vermelidir.

## Görsel yön

- Açık, sıcak ve editoryal.
- Ana zemin: kırık beyaz `#F2EFE7`.
- Kart yüzeyi: `#FCFBF7`.
- Ana metin: `#1E211D`.
- İkincil metin: `#70736B`.
- Birincil aksan: mercan kırmızısı `#E34332`.
- Olumlu durum: koyu yeşil `#1F6B50`.
- Sol navigasyon: `#20241F`.
- Kenarlık: `#DAD7CE`.
- Başlıklarda Georgia benzeri yüksek kontrastlı serif; arayüz metinlerinde
  Inter/SF Pro benzeri sade sans-serif.
- Kart köşeleri çoğunlukla 18–20 px; konturlar ince, gölgeler çok hafif.
- Emoji ağırlıklı görünüm kullanmayın. Basit tek renkli ikonlar tercih edin.
- Fotoğraflar sıcak, doğal, sakin ve premium Japonya seyahat editoryali
  karakterinde olmalıdır.

## Yerleşim

### Masaüstü

- 238 px sabit koyu sol menü.
- Üstte 74 px yapışkan araç çubuğu.
- Ana içerik maksimum 1440 px genişlikte.
- Sayfa dış boşluğu 32–34 px.
- Kartlar arasında 16–18 px boşluk.

### Mobil

- Sol menü ekranın altında ikon tab bar'a dönüşür.
- Üst arama alanı gizlenir.
- İki ve dört sütunlu alanlar tek sütuna iner.
- AI Stüdyo telefon önizlemesi dar ekranlarda gizlenebilir.
- Takvim yatay kaydırılabilir.
- Dokunma hedefleri en az 40 px olmalıdır.

## Sayfa yapıları

### 1. Genel Bakış

- Tarih, kişisel karşılama ve günün operasyon özeti.
- Büyük editoryal fırsat kartı.
- Haftalık hedef skoru ve sıradaki yayın.
- Erişim, etkileşim, takipçi ve kaydetme oranı KPI kartları.
- Yaklaşan içerikler ve son hareketler.

### 2. AI Stüdyo

- İçerik türü: Tek görsel, Carousel, Reel, Story.
- Konu/fikir alanı.
- Ton, hedef ve uzunluk seçimleri.
- Görsel atmosferi seçimleri.
- Ek yönlendirme.
- “Taslağa kaydet” ve ana “İçeriği üret” aksiyonları.
- Masaüstünde sağ tarafta gerçek zamanlı Instagram telefon önizlemesi.

### 3. Takvim

- Aylık görünüm, önceki/sonraki ay ve “Bugün” aksiyonu.
- Tarih hücrelerinde küçük görselli içerik kartları.
- İçerik türleri ve durumları renklerle ayrılır.
- Üretim sürümünde kartlar sürüklenebilir olmalıdır.

### 4. Kütüphane

- Tümü, Görseller, Carousel, Reels ve Taslaklar filtreleri.
- Sıralama ve medya yükleme.
- 4:5 oranlı büyük görsel kartları.
- Durum, tarih, format ve üç nokta menüsü.
- Çoklu seçim için kart üstü dairesel seçim kontrolü.

### 5. Yayın Kuyruğu

- Kanban yapısı: Taslaklar, Onay bekliyor, Planlandı.
- Görselli veya metin ağırlıklı içerik kartları.
- Onaylama, düzenleme ve planlama aksiyonları.
- Otomasyon açık/kapalı durumu.

### 6. Analiz

- Dört üst seviye KPI.
- Haftalık etkileşim/erişim grafiği.
- AI tarafından üretilmiş, uygulanabilir içerik içgörüleri.
- İçgörüden doğrudan yeni içerik üretme aksiyonu.

### 7. Ayarlar

- Sol iç menü: Bağlı hesaplar, Yayın ayarları, AI marka sesi,
  Bildirimler, Takım ve erişim.
- Instagram bağlantısı ve TikTok bağlama kartı.
- Otomatik yayın, akıllı saat önerileri ve haftalık özet anahtarları.

## Temel davranışlar

- Sol menü tek sayfalı uygulama içinde sayfaları değiştirir.
- Aktif navigasyon öğesi açık renkli bir kapsül ile belirtilir.
- Chip gruplarında aynı anda tek seçenek aktiftir.
- Birincil aksiyonlar mercan kırmızısıdır.
- Başarılı eylemler kısa süreli toast bildirimi gösterir.
- Yükleme, boş, hata ve başarı durumları üretim sürümünde ayrıca tasarlanmalıdır.
- Klavye odağı belirgin olmalı; yalnızca renge dayalı durum anlatımı
  yapılmamalıdır.

## Görsel kaynak

`japan-editorial-grid.png`, 3 sütun × 2 satır tek bir fotoğraf atlasıdır:

1. Kyoto/Gion
2. Torii kapıları
3. Tokyo gecesi
4. Ramen
5. Fuji
6. Nara geyiği

Prototip bu görselleri `background-size: 300% 200%` ve farklı
`background-position` değerleriyle kırpar.

## Referans ekranlar

`screens/all-pages.png` tüm masaüstü sayfalarını bir arada gösterir. Ayrıntılı
karşılaştırma için `screens/overview.png`, `studio.png`, `calendar.png`,
`library.png`, `queue.png`, `analytics.png`, `settings.png` ve
`mobile-overview.png` dosyalarını kullanın.
