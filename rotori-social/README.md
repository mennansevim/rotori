# rotori-social

Rotori'nin sosyal içerik, Reels, Story kartı, otomasyon ve yayın yönetimi
ayağıdır. Kaynak kod doğrudan monorepo içindeki bu dizinden geliştirilir ve
dağıtılır; başka bir proje yoluna bağımlı değildir.

Temel bileşenler:

- `src/`: içerik üretimi, scheduler, yayın entegrasyonları ve web API
- `src/web/static/dashboard/`: güncel operasyon paneli
- `data/`: otomasyon ayarı ve yerel kuyruk durumu
- `tests/`: API, scheduler ve dashboard regresyon testleri
- `docs/`: sosyal ürünün mimarisi, aktif işi ve karar günlüğü

Kurulum ve çalışma ayrıntıları için önce `docs/CLAUDE.md`, ardından
`docs/ARCHITECTURE.md` okunmalıdır.
