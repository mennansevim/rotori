# Faz 2 — Çok kullanıcılı yayın

## URL stratejisi

| Path | Açıklama |
|------|----------|
| `/` | Klasik `index.html` veya trip listesi |
| `/viewer/` | JSON tabanlı mobil rehber (PWA) |
| `/planner/` | Planlayıcı dashboard |
| `/t/:tripId` | (nginx rewrite) → `/viewer/?trip=:tripId` |
| `/plan/:tripId` | Planner + auth (Faz 2) |
| `/u/:userId` | Kullanıcının seyahat listesi (Faz 2) |

## API

Stub: [`apps/api/src/server.ts`](../apps/api/src/server.ts)

```
GET  /api/trips/:id     → data/trips/{id}.json
POST /api/trips         → 501 (yeni seyahat + auth)
PUT  /api/trips/:id     → 501 (güncelleme + auth)
```

Çalıştırma: `cd apps/api && npm run dev` (port `3920`).

## Auth (öneri)

- Aile kullanımı: trip başına 4–6 haneli PIN, `Authorization: Bearer <pin>`
- Planner yazma işlemleri PIN gerektirir; viewer herkese açık olabilir
- Alternatif: magic link e-posta (Faz 2+)

## Veri

- Şimdilik: `data/trips/{slug}.json` + git deploy
- Sonra: SQLite `trips` tablosu (`id`, `slug`, `owner_id`, `json`, `updated_at`)

## nginx örnek

```nginx
location /api/ {
  proxy_pass http://127.0.0.1:3920;
}
location /viewer/ {
  alias /var/www/japan-trip/dist/viewer/;
}
location /planner/ {
  alias /var/www/japan-trip/dist/planner/;
}
location ~ ^/t/([^/]+)$ {
  return 302 /viewer/?trip=$1;
}
```
