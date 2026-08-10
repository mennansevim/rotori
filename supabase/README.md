# Supabase Kurulumu — Faz 1

Bu klasör, Japan-Trip'in Flutter + Supabase mimarisine geçişindeki **backend** parçasıdır. Faz 1'in çıktısı: hesap oluşturma + `plans` tablosu + izolasyon (RLS) + realtime yayını.

## 1) Supabase projesi oluştur

1. https://supabase.com → **New Project**
2. Region: Frankfurt (EU) ya da London — kullanıcı kitlesine yakın olsun.
3. **Database password**'ü güvenli bir yerde tut (Postgres direct erişim için).
4. Proje hazır olunca **Project Settings → API** altından şunları not al:
   - `Project URL` (ör. `https://xxxx.supabase.co`)
   - `anon public` key (client'ta kullanılır)
   - `service_role` key (⚠️ sunucu tarafı; Flutter'da KULLANMA)

Bu iki değeri Flutter'da `.env` / `--dart-define` ile geçireceğiz (Faz 2).

## 2) Şemayı uygula

**Yol A — Dashboard (hızlı, tek seferlik):**
Dashboard → **SQL Editor** → `migrations/0001_init.sql` içeriğini yapıştır → **Run**. Idempotent; tekrar çalıştırılabilir.

**Yol B — Supabase CLI (önerilen, versiyonlu):**
```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <proje-ref>
supabase db push          # migrations/*.sql'i uygular
```

## 3) Auth Provider'ları aç

Dashboard → **Authentication → Providers**

### E-posta / şifre (varsayılan)
- **Enable email provider**: açık
- **Confirm email**: dev'de kapat, prod'da aç

### Sign in with Apple (App Store için ŞART)
- Apple Developer hesabı gerekir. Dashboard'da adım adım rehber var: **Providers → Apple → Configure**.
- Kısa yol:
  1. Apple Developer → **Certificates, IDs & Profiles** → yeni **Services ID** (ör. `com.mennansevim.rotori.web`).
  2. **Sign In with Apple** özelliğini etkinleştir; return URL: `https://<proje-ref>.supabase.co/auth/v1/callback`.
  3. **Key** oluştur (Sign in with Apple key), `.p8` dosyasını indir.
  4. Supabase Dashboard'a **Services ID**, **Team ID**, **Key ID**, **.p8 içeriği**'ni gir.
- iOS uygulamasında native "Sign in with Apple" butonu Faz 2'de eklenir; Supabase native token doğrulaması yapar.

### Google (isteğe bağlı)
- **Google Cloud Console** → OAuth 2.0 Client (Web + iOS + Android) → Supabase callback URL'sini authorized redirect'e ekle.
- Client ID + Secret'ı Dashboard'a gir.

## 4) Realtime'ı doğrula

Dashboard → **Database → Replication** → `supabase_realtime` publication altında **plans** görünmeli. (Migration bunu otomatik ekliyor — el ile dokunmaya gerek yok.)

## 5) RLS izolasyonunu doğrula (kabul testi)

Dashboard → **SQL Editor**:
```sql
-- 1) İki test kullanıcısı oluştur (Auth ekranından ya da SQL ile).
-- 2) Kullanıcı A olarak login, bir plan ekle:
insert into public.plans (doc) values ('{"title":"A''nın planı"}'::jsonb);

-- 3) Kullanıcı B'ye geç ve A'nın planını görmeye çalış:
select id, title, doc->>'title' from public.plans;
-- ✅ Boş dönmeli. RLS başkasının satırını göstermez.

-- 4) B, A'nın id'siyle güncellemeye çalışsın:
update public.plans set doc = '{"hack":true}'::jsonb where owner_id = '<A_uid>';
-- ✅ 0 satır etkilenmeli.
```

Bu üç sonuç görülüyorsa izolasyon çalışıyor demektir.

## Şema özeti

```
auth.users (Supabase yönetir)
    │
    ├── profiles (kozmetik: display_name, @username)
    │   RLS: kendi profilini oku/yaz
    │
    └── plans (owner_id → auth.users.id)
        RLS: kendi planlarını oku/yaz/sil
        Realtime: aynı satıra abonelik ile cihazlar arası canlı senkron
        Trigger:
          - updated_at otomatik
          - version otomatik artar (doc değiştiğinde)
```

**Kritik nokta:** `owner_id` kolonunun varsayılanı `auth.uid()`. Flutter'dan `supabase.from('plans').insert({'doc': ...})` yeterli — `owner_id` otomatik oturur.

## Sonraki adım

Faz 2 → Flutter iskeleti (`mobile/`), `supabase_flutter` bağlantısı, login/register ekranları. Bu klasör orada tüketilecek.
