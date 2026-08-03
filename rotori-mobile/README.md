# Japan-Trip · Flutter istemci

Flutter + Supabase tek kod tabanı: iOS + Android + Web.

## Klasör yapısı (Faz 2 sonu)

```
mobile/
├── pubspec.yaml
├── analysis_options.yaml
├── .env.example
├── lib/
│   ├── main.dart              # Supabase init + MaterialApp.router
│   ├── env.dart               # --dart-define okuyucu
│   ├── theme.dart             # Koyu tema (viewer'ın :root token'larıyla uyumlu)
│   ├── core/
│   │   ├── supabase_client.dart   # Riverpod provider'ları (client + auth stream)
│   │   └── router.dart            # GoRouter + auth redirect
│   └── features/
│       ├── auth/
│       │   ├── auth_repository.dart   # tek giriş noktası (Apple ilerisi)
│       │   └── auth_screen.dart       # Login / Kayıt (email + şifre)
│       └── home/
│           └── home_screen.dart       # Faz 5'te "Planlarım"a dönüşür
```

## İlk kurulum

### 1) Flutter SDK

```bash
brew install --cask flutter
flutter doctor    # tüm satırlar ✓ olmalı
```

### 2) Platform kabuklarını üret

Bu depoda sadece `lib/` + `pubspec.yaml` bulunur. Platform (iOS/Android/Web) klasörlerini `flutter create` üretir; `lib/` dosyalarına dokunmaz:

```bash
cd mobile
flutter create --org com.mennansevim --project-name japan_trip \
  --platforms=ios,android,web .
flutter pub get
```

### 3) Supabase env

Supabase Dashboard → **Project Settings → API**'den değerleri al ve
`flutter run` komutuna `--dart-define` ile geçir:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Değerleri tekrar tekrar yazmamak için VSCode `launch.json` veya
`.vscode/settings.json` içinde saklayabilirsin. Ya da `mobile/.env.example`
kopyalayıp `.env` yap, kendi shell'ine `export` ederek `$SUPABASE_URL`
şeklinde referans ver.

## Doğrulama (Faz 2)

1. `flutter run -d chrome --dart-define=...` → tarayıcıda login ekranı açılmalı.
2. Bir e-posta + şifre ile **Kayıt ol** → Supabase Dashboard → Authentication → Users'ta yeni kullanıcı görünmeli.
3. Otomatik giriş yapıp `HomeScreen`'e düşmeli; UUID ekranda görünür.
4. **Çıkış yap** → login ekranına döner.
5. Supabase SQL Editor'de:
   ```sql
   select id, email from auth.users;
   select id, display_name from profiles;
   select user_id, xp, level from user_stats;
   ```
   Yeni kullanıcı için üç satır da olmalı (0001 + 0002 trigger'ları).

## Sıradaki

- **Faz 3** — `packages/shared`'daki 35 TS dosyasının Dart portu (`lib/domain/`).
- **Faz 4** — Drift ile offline yerel DB + `PlansRepository` (sync).
- **Faz 5** — Planlarım listesi + planner/viewer ekranları.

Detaylı yol haritası için repo kökündeki plan: `~/.claude/plans/witty-exploring-mochi.md`.
