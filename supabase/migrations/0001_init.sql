-- ============================================================
-- Japan-Trip · İlk şema
-- ============================================================
-- Amaç:
--   - Her kullanıcı Supabase Auth ile giriş yapar (Apple/Google/e-posta).
--   - "Plan" (= Trip JSON) tek bir jsonb kolonda tutulur, sahibine bağlıdır.
--   - RLS ile bir kullanıcı yalnızca kendi planlarını okur/yazar.
--   - Realtime, planların (aynı kullanıcının farklı cihazları) canlı senkronu için açılır.
--
-- Ön koşul:
--   Supabase projesinde uzantılar zaten yüklüdür. Yine de idempotent olsun diye
--   pgcrypto'yu garanti ediyoruz (gen_random_uuid için).

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1) profiles — kozmetik: gösterim adı ve isteğe bağlı @username.
--    KİMLİK anahtarı bu tablo değil, auth.users.id (UUID). Bu tablo yalnızca
--    "Mennan'ın planı" göstermek / paylaşım linkleri (@handle) içindir.
-- ------------------------------------------------------------
create table if not exists public.profiles (
    id            uuid        primary key references auth.users(id) on delete cascade,
    username      text        unique,
    display_name  text,
    avatar_url    text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    constraint profiles_username_format
      check (username is null or username ~ '^[a-zA-Z0-9_-]{3,32}$')
);

comment on table  public.profiles is 'Kullanıcı için kozmetik profil. Kimlik = auth.users.id.';
comment on column public.profiles.username is 'İsteğe bağlı handle (a-zA-Z0-9_-, 3-32). Paylaşım için.';

-- ------------------------------------------------------------
-- 2) plans — ana veri: Trip JSON (schema.ts / Dart Trip modeli ile birebir).
--    owner_id varsayılanı auth.uid() — Flutter'dan insert ederken göndermek şart değil.
--    version + updated_at ile basit optimistic concurrency (last-write-wins + uyarı).
-- ------------------------------------------------------------
create table if not exists public.plans (
    id          uuid        primary key default gen_random_uuid(),
    owner_id    uuid        not null references auth.users(id) on delete cascade
                            default auth.uid(),
    slug        text,
    title       text,       -- doc->>'title' denormalize (liste ekranı için ucuz sorgu)
    doc         jsonb       not null,
    version     bigint      not null default 1,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

comment on table  public.plans is 'Trip JSON (doc jsonb). Sahibi = owner_id. RLS ile izole.';
comment on column public.plans.doc is 'Trip modeli (Dart Trip.toJson() / TS tripSchema ile birebir).';
comment on column public.plans.version is 'Optimistic concurrency için monoton sayaç. save öncesi client karşılaştırır.';

-- Hızlı liste (kullanıcı başına, son güncelleneni önce)
create index if not exists plans_owner_updated_idx
  on public.plans (owner_id, updated_at desc);
-- Slug ile per-user unique (opsiyonel URL için)
create unique index if not exists plans_owner_slug_uniq
  on public.plans (owner_id, slug)
  where slug is not null;

-- ------------------------------------------------------------
-- 3) updated_at trigger — profiles/plans için otomatik dokunma zamanı
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists plans_touch_updated_at on public.plans;
create trigger plans_touch_updated_at
  before update on public.plans
  for each row execute function public.touch_updated_at();

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- 4) plans.version otomatik artır — update sırasında client version göndermese bile
-- ------------------------------------------------------------
create or replace function public.bump_plan_version()
returns trigger
language plpgsql
as $$
begin
  if new.doc is distinct from old.doc then
    new.version = old.version + 1;
  end if;
  return new;
end;
$$;

drop trigger if exists plans_bump_version on public.plans;
create trigger plans_bump_version
  before update on public.plans
  for each row execute function public.bump_plan_version();

-- ------------------------------------------------------------
-- 5) Yeni kullanıcı → profil satırı otomatik oluştur
--    (auth.users'a insert olduğunda tetiklenir)
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',
                            new.raw_user_meta_data->>'name',
                            null))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- 6) Row-Level Security — kimlik izolasyonu
--    Her kullanıcı yalnızca kendi profilini ve planlarını görür/yazar.
-- ------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.plans    enable row level security;

-- profiles: kullanıcı kendi profilini okur/yazar (username public okumaya izin vermiyoruz;
-- @handle çözümlemesi için ileride ayrı bir "public read only" policy eklenebilir)
drop policy if exists "profiles_own_select" on public.profiles;
drop policy if exists "profiles_own_update" on public.profiles;
drop policy if exists "profiles_own_insert" on public.profiles;

create policy "profiles_own_select"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_own_insert"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_own_update"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- plans: tam sahiplik (select/insert/update/delete)
drop policy if exists "plans_own_all" on public.plans;
create policy "plans_own_all"
  on public.plans for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ------------------------------------------------------------
-- 7) Realtime yayınına ekle — Flutter aboneliklerinin çalışması için
--    (Supabase varsayılan olarak supabase_realtime publication'u sağlar)
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    -- plans tablosunu ekle (varsa yeniden eklemez)
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'plans'
    ) then
      execute 'alter publication supabase_realtime add table public.plans';
    end if;
  end if;
end $$;
