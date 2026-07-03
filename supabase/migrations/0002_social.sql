-- ============================================================
-- Japan-Trip · Sosyal katman: sohbet odaları + XP + moderasyon
-- ============================================================
-- Amaç:
--   - Aynı dönemde Japonya'da olacak yolcuların otomatik sohbet odalarında
--     buluşması (dönem odası: ülke + yıl-ay bazlı; ör. "JP-2026-09").
--   - Sunucu tarafında XP + seviye (client'ta hesap, sunucuya senkron; leaderboard).
--   - Basit moderasyon: rapor + blok + mesaj silme.
--   - Realtime chat_messages ve chat_memberships tabloları için açılır.

-- ------------------------------------------------------------
-- 1) user_stats — sunucu tarafı XP + seviye + rozetler
--    Bugün client'ta userStats.ts'te tutuluyor. Sunucuya taşınınca:
--     - cihazlar arası senkron
--     - leaderboard (aynı dönem odasındakiler arası "en fazla XP")
--     - ödül sistemi doğrulanabilir
-- ------------------------------------------------------------
create table if not exists public.user_stats (
    user_id      uuid        primary key references auth.users(id) on delete cascade,
    xp           integer     not null default 0,
    level        integer     not null default 1,
    badges       jsonb       not null default '[]'::jsonb,  -- BadgeId[]
    action_counts jsonb      not null default '{}'::jsonb,  -- {actionId: count}
    updated_at   timestamptz not null default now()
);

comment on table  public.user_stats is 'Kullanıcı XP/seviye/rozetleri. Client hesaplar, sunucu authoritatif kopya + leaderboard.';

drop trigger if exists user_stats_touch_updated_at on public.user_stats;
create trigger user_stats_touch_updated_at
  before update on public.user_stats
  for each row execute function public.touch_updated_at();

-- Yeni kullanıcıya otomatik stats satırı (0002 uygulandığında zaten var olan
-- kullanıcılar için de aşağıda backfill var).
create or replace function public.handle_new_user_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_stats (user_id) values (new.id)
    on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_stats on auth.users;
create trigger on_auth_user_created_stats
  after insert on auth.users
  for each row execute function public.handle_new_user_stats();

-- Mevcut kullanıcılar için backfill
insert into public.user_stats (user_id)
select id from auth.users
on conflict (user_id) do nothing;

-- ------------------------------------------------------------
-- 2) chat_rooms — sohbet odaları
--    kind:
--      'period'    → dönem odası: ülke + yıl-ay (ör. "JP-2026-09")
--                    slug ve chat_rooms.slug unique.
--      'city'      → ileride: şehir + tarih penceresi
--      'private'   → ileride: DM
--
--    period odaları OTOMATİK oluşur: kullanıcı plana bir Japonya ziyareti
--    eklediğinde ensure_period_room(country, start_date, end_date) çağrılır,
--    kapsanan her ay için oda oluşturulur/varsa dokunulmaz ve üyelik açılır.
-- ------------------------------------------------------------
create table if not exists public.chat_rooms (
    id          uuid        primary key default gen_random_uuid(),
    kind        text        not null check (kind in ('period','city','private')),
    slug        text        unique,   -- ör. 'JP-2026-09'
    title       text        not null,
    country     text,                  -- ISO2 (JP)
    period_ym   text,                  -- 'YYYY-MM' (period odaları için)
    city        text,
    created_at  timestamptz not null default now()
);

comment on table  public.chat_rooms is 'Sohbet odaları. period = ülke+ay bazlı otomatik; city/private ilerisi.';

create unique index if not exists chat_rooms_period_uniq
  on public.chat_rooms (country, period_ym)
  where kind = 'period';

-- ------------------------------------------------------------
-- 3) chat_memberships — kullanıcı-oda ilişkisi (üyelik + okundu-durumu)
-- ------------------------------------------------------------
create table if not exists public.chat_memberships (
    room_id       uuid        not null references public.chat_rooms(id) on delete cascade,
    user_id       uuid        not null references auth.users(id) on delete cascade,
    joined_at     timestamptz not null default now(),
    last_read_at  timestamptz not null default now(),
    muted         boolean     not null default false,
    primary key (room_id, user_id)
);

create index if not exists chat_memberships_user_idx on public.chat_memberships (user_id);

-- ------------------------------------------------------------
-- 4) chat_messages — mesajlar (metin; medya ilerisi)
-- ------------------------------------------------------------
create table if not exists public.chat_messages (
    id          uuid        primary key default gen_random_uuid(),
    room_id     uuid        not null references public.chat_rooms(id) on delete cascade,
    author_id   uuid        not null references auth.users(id) on delete cascade default auth.uid(),
    body        text        not null check (length(body) between 1 and 2000),
    reply_to    uuid        references public.chat_messages(id) on delete set null,
    created_at  timestamptz not null default now(),
    edited_at   timestamptz,
    deleted_at  timestamptz            -- soft delete (moderasyon)
);

create index if not exists chat_messages_room_time_idx
  on public.chat_messages (room_id, created_at desc)
  where deleted_at is null;

-- ------------------------------------------------------------
-- 5) user_blocks — kullanıcı bloku (mesajları görmesin/görülmesin)
-- ------------------------------------------------------------
create table if not exists public.user_blocks (
    blocker_id  uuid        not null references auth.users(id) on delete cascade default auth.uid(),
    blocked_id  uuid        not null references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

-- ------------------------------------------------------------
-- 6) message_reports — kullanıcı raporları (moderasyon kuyruğu)
--    Basit MVP: rapor gelen mesaj admin panelinde/manuel bakılır.
-- ------------------------------------------------------------
create table if not exists public.message_reports (
    id          uuid        primary key default gen_random_uuid(),
    message_id  uuid        not null references public.chat_messages(id) on delete cascade,
    reporter_id uuid        not null references auth.users(id) on delete cascade default auth.uid(),
    reason      text        not null check (length(reason) between 1 and 500),
    status      text        not null default 'open' check (status in ('open','resolved','dismissed')),
    created_at  timestamptz not null default now(),
    unique (message_id, reporter_id)  -- aynı kullanıcı aynı mesajı bir kez raporlar
);

-- ------------------------------------------------------------
-- 7) Kapsül fonksiyonlar
-- ------------------------------------------------------------

-- Yeni ay bulunca gerekli oda(ları) ensure et. Kullanıcı planındaki
-- ziyaret aralığını verir; kapsanan her yıl-ay için period odası
-- oluşturulur/varsa döner ve kullanıcı membership'i açılır.
--
-- Örnek: ensure_period_rooms('JP', date '2026-09-14', date '2026-10-02')
--   → 'JP-2026-09' ve 'JP-2026-10' odalarına üyelik verir.
create or replace function public.ensure_period_rooms(
  p_country  text,
  p_start    date,
  p_end      date
)
returns setof public.chat_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  cur date := date_trunc('month', p_start)::date;
  r   public.chat_rooms;
  ym  text;
  title text;
begin
  if p_country is null or p_start is null or p_end is null or p_end < p_start then
    return;
  end if;
  if auth.uid() is null then
    raise exception 'ensure_period_rooms: auth.uid() gerekli';
  end if;

  while cur <= p_end loop
    ym := to_char(cur, 'YYYY-MM');
    title := format('%s · %s', p_country, ym);

    insert into public.chat_rooms (kind, slug, title, country, period_ym)
    values ('period', format('%s-%s', p_country, ym), title, p_country, ym)
    on conflict (country, period_ym) where kind = 'period' do nothing;

    select * into r from public.chat_rooms
      where kind='period' and country=p_country and period_ym=ym;

    insert into public.chat_memberships (room_id, user_id)
    values (r.id, auth.uid())
    on conflict do nothing;

    return next r;
    cur := (cur + interval '1 month')::date;
  end loop;
end;
$$;

-- Odadaki üye sayısını hızlıca döndürür (client'ta rozet için).
create or replace function public.room_member_count(p_room uuid)
returns integer
language sql
stable
as $$
  select count(*)::int from public.chat_memberships where room_id = p_room;
$$;

-- ------------------------------------------------------------
-- 8) RLS — sosyal tablolar
-- ------------------------------------------------------------
alter table public.user_stats       enable row level security;
alter table public.chat_rooms       enable row level security;
alter table public.chat_memberships enable row level security;
alter table public.chat_messages    enable row level security;
alter table public.user_blocks      enable row level security;
alter table public.message_reports  enable row level security;

-- user_stats: kendini oku/yaz + leaderboard için public read (opsiyonel).
-- Ödünleşme: XP herkese görünür olsun mu? MVP'de EVET (herkese SELECT).
drop policy if exists user_stats_public_read on public.user_stats;
drop policy if exists user_stats_own_write   on public.user_stats;

create policy user_stats_public_read
  on public.user_stats for select
  using (true);

create policy user_stats_own_write
  on public.user_stats for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
-- insert trigger yaptığı için ayrı insert policy gereksiz; ancak upsert için:
create policy user_stats_own_insert
  on public.user_stats for insert
  with check (auth.uid() = user_id);

-- chat_rooms: bir odayı üyeleri okuyabilir. Oluşturma sadece fonksiyon üzerinden
-- (definer) yapılır, doğrudan insert yasak.
drop policy if exists chat_rooms_member_select on public.chat_rooms;
create policy chat_rooms_member_select
  on public.chat_rooms for select
  using (
    exists (
      select 1 from public.chat_memberships m
      where m.room_id = chat_rooms.id and m.user_id = auth.uid()
    )
  );

-- chat_memberships: kendi üyeliklerini yönet
drop policy if exists chat_memberships_own_all on public.chat_memberships;
create policy chat_memberships_own_all
  on public.chat_memberships for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- chat_messages:
--   SELECT: üyesi olduğun odanın mesajları + blokladıklarını GİZLE
--   INSERT: üyesi olduğun odaya, kendi adına
--   UPDATE/DELETE: sadece kendi mesajlarını (edit ~ 15 dk; DB'de değil client'ta)
drop policy if exists chat_messages_member_select on public.chat_messages;
drop policy if exists chat_messages_member_insert on public.chat_messages;
drop policy if exists chat_messages_own_update    on public.chat_messages;
drop policy if exists chat_messages_own_delete    on public.chat_messages;

create policy chat_messages_member_select
  on public.chat_messages for select
  using (
    deleted_at is null
    and exists (
      select 1 from public.chat_memberships m
      where m.room_id = chat_messages.room_id and m.user_id = auth.uid()
    )
    and not exists (
      select 1 from public.user_blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = chat_messages.author_id
    )
  );

create policy chat_messages_member_insert
  on public.chat_messages for insert
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.chat_memberships m
      where m.room_id = chat_messages.room_id and m.user_id = auth.uid()
    )
  );

create policy chat_messages_own_update
  on public.chat_messages for update
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

create policy chat_messages_own_delete
  on public.chat_messages for delete
  using (author_id = auth.uid());

-- user_blocks: sadece kendi bloklarını
drop policy if exists user_blocks_own_all on public.user_blocks;
create policy user_blocks_own_all
  on public.user_blocks for all
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- message_reports: raporunu yaz + kendi raporlarını gör
drop policy if exists message_reports_own_write on public.message_reports;
drop policy if exists message_reports_own_read  on public.message_reports;

create policy message_reports_own_write
  on public.message_reports for insert
  with check (reporter_id = auth.uid());

create policy message_reports_own_read
  on public.message_reports for select
  using (reporter_id = auth.uid());

-- ------------------------------------------------------------
-- 9) Realtime yayınına ekle (mesajlar + üyelikler + user_stats)
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['chat_messages','chat_memberships','user_stats']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
