# Başka Bir LLM'e Verilecek Prompt

Bu klasördeki `index.html`, `DESIGN-SPEC.md`, `japan-editorial-grid.png` ve
`screens/` referanslarını incele.

Japonya Rüyası projesi için bu tasarımı üretim kalitesinde uygula. Görsel dili,
sayfa hiyerarşisini, metinleri, spacing sistemini, responsive davranışı ve
referans ekranlardaki genel kompozisyonu koru. Projenin mevcut teknoloji
yığınını, klasör yapısını ve API sözleşmelerini değiştirme.

Uygulanacak ekranlar:

1. Genel Bakış
2. AI Stüdyo
3. Takvim
4. Kütüphane
5. Yayın Kuyruğu
6. Analiz
7. Ayarlar

Gereksinimler:

- Demo verilerini projenin gerçek API uçlarına bağla.
- Mevcut içerik üretme, caption, görsel hazırlama, onay, zamanlama, Instagram
  yayınlama, TikTok cross-posting ve analitik işlevlerini koru.
- Tasarımı yeniden yorumlama; referans ekranlara mümkün olduğunca sadık kal.
- Masaüstü, tablet ve mobil kırılımları uygula.
- Erişilebilir navigasyon, form etiketleri, klavye odağı ve yeterli kontrast
  sağla.
- Yükleme, boş, hata, başarı ve işlem devam ediyor durumlarını ekle.
- Kalıcı veriler için projenin mevcut backend'ini kullan; demo local state'i
  üretim çözümü olarak bırakma.
- Mevcut çalışan davranışları kaldırma. Gerekirse eski ve yeni arayüzü geçici
  bir özellik bayrağıyla birlikte çalıştır.
- Uygulamayı çalıştır, tüm sayfaları ve ana etkileşimleri tarayıcıda test et.
- Sonuçta değiştirdiğin dosyaları ve hangi API'leri hangi bileşenlere bağladığını
  özetle.

Tasarımın tek dosyalı prototipi `index.html` içindedir. Onu doğrudan üretim
mimarisi olarak kullanmak zorunda değilsin; bileşenlere ayırabilirsin. Ancak
görsel sonuç ve davranış tasarım spesifikasyonuyla uyumlu kalmalıdır.
