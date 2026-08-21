# Rehber Sekmesi Yeniden Tasarım Özeti

## Amaç

Rehber sekmesini mevcut beşli ana sekme kabuğunun içinde tutarak daha hızlı
taranan, Apple tarzı sakin bir bilgi mimarisine taşımak.

## Onaylanan düzen

- Büyük ve sade `Rehber` başlığı ile kısa, geziye bağlı açıklama.
- Başlığın hemen altında bütün rehber içeriğinde çalışan arama.
- `Hızlı erişim` alanında Acil Durum, Suica, Para ve İnternet konuları.
- Bütün konuların tek bir inset-group listesinde ikon, başlık, madde sayısı ve
  chevron ile gösterilmesi.
- Konu seçildiğinde aynı Rehber sekmesi içinde geri düğmeli temiz detay görünümü;
  üst durum çubuğu ve sabit alt menü yerinde kalır.
- `Seyahat öncesi hallet` alanı Rehber içinde gösterilmez; Keşfet menüsündeki
  ayrı erişimi korunur.
- Çocuklu geziye özel maddelerin mevcut filtreleme davranışı korunur.
- En az 44 dp dokunma alanı, Dynamic Type ile taşmayan metin ve azaltılmış
  hareket tercihine saygı korunur.

## Kapsam dışı

- Rehber veri içeriğini veya dış bağlantıları değiştirmek.
- Japonca, Keşfet veya drawer mimarisini bu iş içinde yeniden tasarlamak.
- Yeni paket, ağ servisi ya da kalıcı veri modeli eklemek.
