# Japonya Seyahat Rehberi

Statik rehber (`index.html`), JSON tabanlı mobil viewer ve planlayıcı dashboard.

## Hızlı başlangıç

```bash
npm install
npm run dev:viewer    # http://localhost:5173/viewer/
npm run dev:planner   # http://localhost:5174/planner/ (port vite’a göre değişebilir)
```

Üretim build:

```bash
npm run build
# çıktı: dist/ (index.html, data/, viewer/, planner/)
```

HTML’den JSON migrasyon:

```bash
npm run migrate
```

## Deploy (Raspberry Pi)

Mevcut akış: Cursor’da `commit`, `push`, `deploy` → [`tools/review-commit`](tools/review-commit).

Pi’de örnek deploy komutu (`.env` içinde `PI_DEPLOY_CMD`):

```bash
git pull origin main && npm ci && npm run build && rsync -a dist/ /var/www/japan-trip/
```

Veya yalnızca statik `index.html` kullanıyorsanız önceki `docker compose` komutunuzu koruyun; build çıktısını webroot’a kopyalayın.

## Yapı

- `index.html` — klasik rehber (seyahat tamamlandı sayacı, bugünkü güne kaydırma)
- `data/trips/*.json` — seyahat planı
- `apps/viewer` — mobil PWA rehber
- `apps/planner` — 7 adımlı planlayıcı + gün editörü
- `packages/shared` — tipler, zod, kurallar
- `apps/api` — Faz 2 API stub
- `docs/PHASE2-ROUTING.md` — çok kullanıcılı URL/API notları

## Planlayıcı özellikleri

1. Seyahat özeti (tarih, tempo, kişi sayısı)
2. Ulaşım ve otel
3. Biletler
4. Yemek tercihleri ve bütçe
5. Must-see ve max adım
6. Gün editörü — aktiviteyi başka güne taşıma, taksi önerisi
7. JSON export/import ve viewer önizleme

Planner değişiklikleri `localStorage` (`trip:sevimm-japan-2026`) ile viewer’a yansır.
