# Mobil Gözlemlenebilirlik Kurulumu

## 1. Supabase

Kök dizindeki `supabase/migrations/0009_analytics_observability.sql`
migration'ını hedef projeye uygula. İki tablo oluşur:

- `analytics_events`: uygulama/ekran yaşam döngüsü ve genel ürün olayları
- `route_generation_logs`: her rota denemesinin `started`, `succeeded` veya
  `failed` fazı; sadeleştirilmiş request/result JSON'u ve metrikleri

Mobil rol yalnız kendi kullanıcısı adına INSERT yapabilir. Analiz sorguları
Supabase Dashboard SQL Editor veya güvenli bir server-side `service_role`
ortamından çalıştırılır; servis anahtarı uygulamaya konmaz.

## 2. Sentry

1. Sentry'de Flutter projesi oluştur; veri bölgesi tercihen EU olsun.
2. Public DSN'i release ortamına secret olarak ekle:

```text
SENTRY_DSN=https://PUBLIC_KEY@o0.ingest.sentry.io/0
SENTRY_ENVIRONMENT=production
SENTRY_TRACES_SAMPLE_RATE=0.1
```

DSN yoksa uygulama normal çalışır ve Sentry tamamen no-op olur. SDK; varsayılan
PII, ekran görüntüsü, UI ağacı ve otomatik etkileşim breadcrumb'ları kapalı
başlatılır. Rota JSON'u yalnız Supabase'e gider.

## 3. Doğrulama

1. Oturum açıp uygulamayı aç; `analytics_events` içinde `app_open` gör.
2. Bir rota oluştur; aynı `attempt_id` ile `started` ve `succeeded` gör.
3. Request/result JSON'unda uçuş, otel, bilet, not, iletişim, fotoğraf, harita
   URL'si, gerçek GPS veya beslenme tercihinin içeriği olmadığını doğrula.
4. Kontrollü bir test hatasını staging build'de üret; Sentry'de stack trace,
   release/environment ve güvenli ekran breadcrumb'ını doğrula.
5. Ağ kapalıyken rota oluşturup ağı geri aç; yerel outbox'ın kayıtları daha
   sonra gönderdiğini doğrula.

Hazır sorgular `ANALYTICS_QUERIES.md` dosyasındadır.
